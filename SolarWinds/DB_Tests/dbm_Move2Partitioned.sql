IF EXISTS (SELECT [name] FROM sys.procedures WHERE [name] = N'dbm_Move2Partitioned')
DROP PROCEDURE dbm_Move2Partitioned;
GO

CREATE PROCEDURE [dbo].[dbm_Move2Partitioned]
/************************/
/* version 2025-03-13/1 */
/*          BD          */
/************************/
(
 @tab_name NVARCHAR(96),
 @date_from DATE,
 @force_flush BIT = 0,
 @check_retentions BIT = 0,	-- before migration clears data outside of retention intervals
 @get_dates_from_metadata BIT = 0
)
AS
DECLARE @partition_scheme NVARCHAR(128);
DECLARE @partition_function NVARCHAR(128);
DECLARE @error_message VARCHAR(MAX);
DECLARE @error_severity INT;
DECLARE @error_state INT;
DECLARE @is_existing_table BIT;
DECLARE @target_table_name NVARCHAR(96);
DECLARE @source_table_name NVARCHAR(96);
DECLARE @source_retention SMALLINT;
DECLARE @target_retention SMALLINT;
DECLARE @max_retention SMALLINT;
DECLARE @partitioning_column NVARCHAR(64);
DECLARE @part_column_type NVARCHAR(32);
DECLARE @sql NVARCHAR(MAX);
DECLARE @processing_date DATETIME2;
DECLARE @column_name NVARCHAR(64),
        @data_type NVARCHAR(32),
        @aggregate_function NVARCHAR(256),
        @is_grouping_column BIT,
        @is_natural_key BIT,
        @is_nullable BIT,
        @is_partitioning_column BIT,
		@is_derived_metric BIT,
		@is_ranked_metric BIT;
DECLARE @source_view_name NVARCHAR(128);
DECLARE @stg_tab_name NVARCHAR(96);
DECLARE @date_to DATE;
DECLARE @grouping_columns NVARCHAR(512) = '';
DECLARE @date_to_char NVARCHAR(16);
DECLARE @date_from_char NVARCHAR(16);
DECLARE @is_clustered_columnstore BIT;
DECLARE @partition_number INT;
DECLARE @is_target_partition_empty BIT;
DECLARE @is_memory_optimized BIT;
DECLARE @filegroup NVARCHAR(64);
DECLARE @is_alteranyconnection_granted BIT;
DECLARE @min_target_date DATE;
DECLARE @min_source_date DATE;
DECLARE @key_columns NVARCHAR(2000);
DECLARE @delimited_key NVARCHAR(2000);
DECLARE @textual_output NVARCHAR(MAX);
DECLARE @table_with_derived_metric BIT = 0;
DECLARE @rows BIGINT;
DECLARE @on_cols_sql NVARCHAR(4000) = '';
DECLARE @new_line CHAR(2) = CHAR(13) + CHAR(10);

BEGIN
	SET NOCOUNT ON;

	SELECT TOP 1 @filegroup = [Filegroup]
	  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
	 WHERE tspc.TableName = @tab_name
	   AND tspc.TableType = 'Detail'
	;

	SELECT @is_alteranyconnection_granted = COUNT(1)
	  FROM fn_my_permissions(NULL, 'SERVER')
	  WHERE permission_name = 'ALTER ANY CONNECTION'
	;

	IF @filegroup IS NULL 
		BEGIN
			SET @filegroup = '[PRIMARY]';
		END;
	ELSE IF SUBSTRING(@filegroup,0,1) != '['
		BEGIN
			SET @filegroup = '[' + @filegroup + ']';
		END;

	SET @target_table_name = @tab_name + '_Detail_hist';
	SET @source_table_name = @tab_name + '_cur';
	SET @source_view_name = @tab_name + '_Detail';
	SET @stg_tab_name = @tab_name + '_stg';

	/* handle table name */
	SELECT @is_existing_table = COUNT(name)
	  FROM sys.tables WITH (NOLOCK)
	 WHERE name = @target_table_name;
	/* table does not exist */
	IF @is_existing_table = 0
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Table: ' + @target_table_name
			                   + ' does not exist. All parameters:'
							   + ' @tab_name: ' + ISNULL(@tab_name, 'NULL') + ', @date_from: ' + CAST(@date_from AS NVARCHAR(32))
							   ;
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 16, 1) WITH NOWAIT;
			RETURN			
		END;
	ELSE
		BEGIN
			/* load min source (_cur) retention */
			SELECT @source_retention = tspc.RetentionDays	
			  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
			 WHERE tspc.TableType = 'cur'
			   AND tspc.TableName = @tab_name;

			/* handle min target retention */
			/* load available parameters from metadata */
			SELECT @target_retention = tspc.RetentionDays - @source_retention,
				   @partitioning_column = tsc.ColumnName,
				   @part_column_type = tsc.DataType
			  FROM dbm_TimeSeriesConfig tsc WITH (NOLOCK)
			  INNER JOIN dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
					  ON tsc.TableName = tspc.TableName
			 WHERE tspc.TableType = 'Detail'
			   AND tsc.TableName = @tab_name
			   AND tsc.IsPartitioningColumn = 1;	

			/* handle metadata */   
			IF @partitioning_column IS NULL
				BEGIN
					SET @error_message = OBJECT_NAME(@@PROCID) + ': There are no metadata defined in dbm_TimeSeriesConfig or dbm_TimeSerieProcessingConfig for ' + @tab_name + '* tables!';
					INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
					RAISERROR (@error_message, 16, 1) WITH NOWAIT;
					RETURN						
				END;	

			SELECT @is_memory_optimized = is_memory_optimized
			  FROM sys.tables WITH (NOLOCK)
			 WHERE name = @source_table_name;
		END;

	/* DELETE super ancient data polled by mistake before handling dates using DATEADD to prevent error */
	SET @sql = 'DELETE FROM ' + @source_table_name + ' WHERE [' + @partitioning_column + '] < CAST(''20100101'' AS ' + @part_column_type + ')';
	EXEC sp_executesql @sql;
	SET @rows = @@ROWCOUNT;
	/* write related info message into PartitionErrors log table */
	IF @rows > 0
	BEGIN
		SELECT @error_message = OBJECT_NAME(@@PROCID) + ': Super ancient data detected! Deleting ' + CAST(@rows AS NVARCHAR) + ' records older than 2010-01-01 from ' + @source_table_name + ' table!';
		INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
		RAISERROR (@error_message, 1, 10) WITH NOWAIT;
	END;

	/* explicit check whether table contains some derived metric */
	SELECT DISTINCT @table_with_derived_metric = cnf.IsDerivedMetric
	  FROM dbm_TimeSeriesConfig cnf WITH (NOLOCK)
	 WHERE cnf.IsDerivedMetric = 1
	   AND cnf.TableName = @tab_name;

	/* get min target and source date */
	IF @get_dates_from_metadata = 0
		BEGIN
			SET @sql = 'SELECT @min_target_date = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MIN([' + @partitioning_column + '])), ''20000101'') FROM ' + @target_table_name + ' WITH (NOLOCK)';
			EXEC sp_executesql @sql, N'@min_target_date DATE OUTPUT', @min_target_date = @min_target_date OUTPUT;

			SET @sql = 'SELECT @min_source_date = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MIN([' + @partitioning_column + '])), ''20000101'') FROM ' + @source_table_name + ' WITH (NOLOCK)';
			EXEC sp_executesql @sql, N'@min_source_date DATE OUTPUT', @min_source_date = @min_source_date OUTPUT;
		END;
	ELSE
		BEGIN
			--partitioning RIGHT so we have to substract 1 DAY from all range values!
			SELECT @min_target_date = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE))
			  FROM sys.indexes ind WITH(NOLOCK)
			  LEFT JOIN sys.partitions p WITH(NOLOCK)
					 ON ind.object_id = p.object_id
					AND ind.index_id = p.index_id
			  LEFT JOIN sys.data_spaces ds WITH(NOLOCK)
					 ON ind.data_space_id = ds.data_space_id
			  LEFT JOIN sys.partition_schemes sch WITH(NOLOCK)
					 ON sch.data_space_id = ds.data_space_id
			  LEFT JOIN sys.partition_range_values prv WITH(NOLOCK)
					 ON prv.function_id = sch.function_id
					AND prv.boundary_id = p.partition_number
			  LEFT JOIN sys.index_columns ic WITH(NOLOCK)
					 ON (ic.partition_ordinal > 0
					AND ic.index_id = ind.index_id
					AND ic.object_id = ind.object_id)
			 WHERE p.object_id = OBJECT_ID(@target_table_name)
			   AND ind.type IN (0,1,5)
			   AND p.rows > 0
			;

			SELECT @min_source_date = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE))
			  FROM sys.indexes ind WITH(NOLOCK)
			  LEFT JOIN sys.partitions p WITH(NOLOCK)
					 ON ind.object_id = p.object_id
					AND ind.index_id = p.index_id
			  LEFT JOIN sys.data_spaces ds WITH(NOLOCK)
					 ON ind.data_space_id = ds.data_space_id
			  LEFT JOIN sys.partition_schemes sch WITH(NOLOCK)
					 ON sch.data_space_id = ds.data_space_id
			  LEFT JOIN sys.partition_range_values prv WITH(NOLOCK)
					 ON prv.function_id = sch.function_id
					AND prv.boundary_id = p.partition_number
			  LEFT JOIN sys.index_columns ic WITH(NOLOCK)
					 ON (ic.partition_ordinal > 0
					AND ic.index_id = ind.index_id
					AND ic.object_id = ind.object_id)
			 WHERE p.object_id = OBJECT_ID(@source_table_name)
			   AND ind.type IN (0,1,5)
			   AND p.rows > 0
			;
		END;

	/* data in _cur table are older than data in _detail = ancient data polled! */
	IF @min_source_date IS NOT NULL AND @min_target_date IS NOT NULL AND @min_source_date < @min_target_date
		BEGIN
			SELECT @key_columns = ISNULL(@key_columns, '') + '[' + tsc.ColumnName + '],',
			       @delimited_key = ISNULL(@delimited_key, '') + 'CAST([' + tsc.ColumnName + '] AS NVARCHAR(800)) + '','' + '
			  FROM dbm_TimeSeriesConfig tsc WITH (NOLOCK)
			 WHERE tsc.TableName = @tab_name
			   AND tsc.IsNaturalKey = 1
			   AND tsc.IsEnabled = 1
			   AND tsc.IsPartitioningColumn = 0;

			/* select all keys from _cur which are ancient and log them in a message */
			SET @sql = 'SELECT @textual_output = ''' + @key_columns + '[' + @partitioning_column + '];' + ''' ' 
			EXEC sp_executesql @sql, N'@textual_output NVARCHAR(MAX) OUTPUT', @textual_output = @textual_output OUTPUT;
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Ancient data listing from ' + @source_table_name +': ' + @textual_output;

			SET @sql = 'SELECT DISTINCT @textual_output = ' + @delimited_key + 'CAST(CAST([' + @partitioning_column + '] AS DATE) AS NVARCHAR) + '';''' + CHAR(13)
					 + '  FROM ' + @source_table_name + IIF(@is_memory_optimized = 1, ' WITH (SNAPSHOT)', ' WITH (NOLOCK)') + CHAR(13)
					 + ' WHERE [' + @partitioning_column + '] < CAST(''' + CONVERT(NVARCHAR, @min_target_date, 112) + ''' AS ' + @part_column_type + ')';
            EXEC sp_executesql @sql, N'@textual_output NVARCHAR(MAX) OUTPUT', @textual_output = @textual_output OUTPUT;
			SET @error_message = @error_message + @textual_output;
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 1, 10) WITH NOWAIT

			/* DELETE ancient data and log warning */
			SET @sql = 'DELETE FROM ' + @source_table_name + ' WHERE [' + @partitioning_column + '] < CAST(''' + CONVERT(NVARCHAR, @min_target_date, 112) + ''' AS ' + @part_column_type + ')';
			EXEC sp_executesql @sql;
			SET @rows = @@ROWCOUNT;

			SELECT @error_message = OBJECT_NAME(@@PROCID) + ': Data older than already processed dates detected! Deleting ' + CAST(@rows AS NVARCHAR) + ' records older than ' + CONVERT(NVARCHAR, @min_target_date, 112) + ' from ' + @source_table_name + ' table!';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 1, 10) WITH NOWAIT;
		END;

	/* force data flush for memory-optimized table only! */
	IF @force_flush = 1 AND @is_memory_optimized = 1
		SET @date_from = CAST('99990101' AS DATE);
	ELSE
		BEGIN
			/* handle @date_from */
			IF @date_from IS NULL OR @date_from <= CAST(DATEADD(DAY, -1, GETDATE()) AS DATE) 
				SET @date_from = CAST(DATEADD(DAY, -@source_retention, GETDATE()) AS DATE);
			ELSE 
				SET @date_from = CAST(DATEADD(DAY, -@source_retention, @date_from) AS DATE);
		END;

	SET @date_from_char = CONVERT(NVARCHAR, @date_from, 112);

	IF @check_retentions = 1
	BEGIN
		/* get max retention */
		SELECT @max_retention = tspc.RetentionDays
		  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
		 WHERE tspc.TableName = @tab_name AND tspc.TableType = 'Daily';  

		/* remove data older than daily retention */
		SET @sql = 'DELETE ' + @source_table_name + '
				     WHERE [' + @partitioning_column + '] < ''' + CAST(DATEADD(DAY, -(@max_retention - @source_retention), @date_from) AS NVARCHAR(32)) + '''';
		--PRINT @sql;
		EXEC sp_executesql @sql;
	END

	/* partition function and scheme */
	SELECT @partition_scheme = ps.name,
		   @partition_function = pf.name
	  FROM sys.partition_schemes ps WITH (NOLOCK)
	  INNER JOIN sys.partition_functions pf WITH (NOLOCK)
			  ON pf.function_id = ps.function_id
	  INNER JOIN sys.data_spaces ds WITH (NOLOCK)
			  ON ds.data_space_id = ps.data_space_id
	  INNER JOIN sys.indexes i WITH (NOLOCK)
			  ON i.data_space_id = ps.data_space_id
	  INNER JOIN sys.tables t WITH (NOLOCK)
			  ON t.object_id = i.object_id
	 WHERE t.name = @target_table_name
	   AND i.type IN (0,1,5)
	;

	/* @variable table for dynamic data */
	DECLARE @unique_dates TABLE ([Date] DATETIME2 NOT NULL PRIMARY KEY CLUSTERED);
	/* get unique dates from _cur table */
	SET @sql = '
				SELECT DISTINCT CAST([' + @partitioning_column + '] AS DATE) 
				  FROM ' + @source_table_name + '
				 WHERE [' + @partitioning_column + '] < ''' + @date_from_char + '''
				ORDER BY 1 ASC
			   '
	;
	INSERT INTO @unique_dates
    EXEC (@sql);

	/* create empty partitions for new data */	
	DECLARE @min_date DATETIME2;
	DECLARE @max_date DATETIME2;
	
	SELECT @min_date = MIN([Date]),
           @max_date = MAX([Date])
	  FROM @unique_dates;

	SET @sql = 'exec dbm_CreateEmptyPartitions ''' + @target_table_name + ''', @date_from, NULL';
	--PRINT @sql;
	EXEC sp_executesql @sql, N'@date_from DATETIME2', @date_from = @min_date;
	--PRINT @min_date;
	EXEC sp_executesql @sql, N'@date_from DATETIME2', @date_from = @max_date;
	--PRINT @max_date;

	/* metadata for table creation */

	IF @table_with_derived_metric = 0
		/* take into account possible different column order in physical higher-grain tables!!! */
		DECLARE cColumns CURSOR LOCAL FAST_FORWARD READ_ONLY 
		FOR
		SELECT cnf.ColumnName,
			   cnf.DataType,
			   cnf.AggregateFunction,
			   cnf.IsGroupingColumn,
			   cnf.IsNaturalKey,
			   cnf.IsNullable,
			   cnf.IsPartitioningColumn,
			   cnf.IsDerivedMetric,
			   cnf.IsRankedMetric
		  FROM dbm_TimeSeriesConfig cnf WITH (NOLOCK)
		  LEFT JOIN sys.columns c
				 ON c.name = cnf.ColumnName
		  INNER JOIN sys.tables t
			      ON t.object_id = c.object_id
		 WHERE cnf.IsEnabled = 1
		   AND cnf.TableName = @tab_name
		   AND t.name = @target_table_name
		ORDER BY c.column_id
		;
	ELSE
		/* no way how to deal with manually changed tables for derived metrics */
		DECLARE cColumns CURSOR LOCAL FAST_FORWARD READ_ONLY 
		FOR
		SELECT cnf.ColumnName,
			   cnf.DataType,
			   cnf.AggregateFunction,
			   cnf.IsGroupingColumn,
			   cnf.IsNaturalKey,
			   cnf.IsNullable,
			   cnf.IsPartitioningColumn,
			   cnf.IsDerivedMetric,
			   cnf.IsRankedMetric
		  FROM dbm_TimeSeriesConfig cnf WITH (NOLOCK)
		 WHERE cnf.IsEnabled = 1
		   AND cnf.TableName = @tab_name
		ORDER BY cnf.ColumnID
		;

	/* move them in a loop */
	DECLARE cDates CURSOR LOCAL FAST_FORWARD READ_ONLY 
	FOR
	SELECT CAST(ud.Date AS DATE)
	  FROM @unique_dates ud
	ORDER BY CAST(ud.Date AS DATE) ASC
	;

	/* check that this procedure can be executed just once in current moment */
	IF (SELECT APPLOCK_TEST('public', @source_table_name, 'Exclusive', 'Session')) = 1
		BEGIN
			DECLARE @result int;  
			EXEC @result = sp_getapplock  
				 @DbPrincipal = 'public',
				 @Resource = @source_table_name,  
				 @LockMode = 'Exclusive',  
				 @LockOwner = 'Session';  

			OPEN cDates;
			FETCH NEXT FROM cDates
			INTO @processing_date; 
			WHILE @@FETCH_STATUS = 0
			BEGIN			
				BEGIN TRY
					BEGIN TRANSACTION;

					SET @date_from = @processing_date;
					--probably also different number of days per partition( + daysinpart?)
					SET @date_to = DATEADD(DAY, 1, @date_from);	

					SET @date_from_char = CONVERT(NVARCHAR, @date_from, 112);
					SET @date_to_char = CONVERT(NVARCHAR, @date_to, 112);		

					/* get partition number to switch data in */
					SET @sql = 'SELECT @partition_number = $PARTITION.' + @partition_function + '(''' + @date_from_char + ''')';
					--PRINT @sql;
					EXEC sp_executesql @sql, N'@partition_number INT OUTPUT', @partition_number = @partition_number OUTPUT;	

					/* check if target partition is empty */
					SELECT DISTINCT @is_target_partition_empty = CASE WHEN p.rows = 0 THEN 1 ELSE 0 END
					  FROM sys.partitions p WITH(NOLOCK)
					  INNER JOIN sys.tables t WITH(NOLOCK)
							  ON p.object_id = t.object_id
					 WHERE t.name = @target_table_name
					   AND p.partition_number = @partition_number;		

					/* is partitioned table in columnstore index? */
					SELECT @is_clustered_columnstore = COUNT(i.index_id)
					  FROM sys.tables t WITH(NOLOCK)
					  INNER JOIN sys.indexes i WITH(NOLOCK)
							  ON t.object_id = i.object_id
					 WHERE t.name = @target_table_name
					   AND i.type = 5;

					/* if empty then go stage table way */
					IF @is_target_partition_empty = 1
						BEGIN
							/* crate stage table for ccsi */
							IF @is_clustered_columnstore = 1
								BEGIN
									SET @sql = 'CREATE TABLE ' + @stg_tab_name + @new_line + '(' + @new_line;

									OPEN cColumns;
									FETCH NEXT FROM cColumns
									INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
									WHILE @@FETCH_STATUS = 0
									BEGIN		
										IF @is_partitioning_column = 1
											BEGIN
												SET @partitioning_column = @column_name;
											END;

										IF @is_nullable = 1
											BEGIN
												SET @sql = @sql + '[' + @column_name + '] ' + @data_type + ' ' + 'NULL,' + @new_line;
											END;
										ELSE
											BEGIN
												SET @sql = @sql + '[' + @column_name + '] ' + @data_type + ' ' + 'NOT NULL,' + @new_line;
											END;

										FETCH NEXT FROM cColumns
										INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
									END;
									CLOSE cColumns;

									SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-LEN(@new_line)) + @new_line;
									SET @sql = @sql + ') ON ' + @filegroup;
									--PRINT @sql;
									EXEC sp_executesql @sql;

									/* add clustered columnstore index */
									SET @sql = 'CREATE CLUSTERED COLUMNSTORE INDEX [CCSI_' + @stg_tab_name + '] ON [' + @stg_tab_name + '] ON ' + @filegroup;
									--PRINT @sql;
									EXEC sp_executesql @sql;

								END;

							/*******************************/
							SET @sql = 'WITH _Detail' + @new_line + 'AS' + @new_line + '(' + @new_line + 'SELECT' + @new_line;

							OPEN cColumns;
							FETCH NEXT FROM cColumns
							INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							WHILE @@FETCH_STATUS = 0
							BEGIN		
								IF @is_partitioning_column = 1
									BEGIN
										SET @partitioning_column = @column_name;				
										SET @sql = @sql + '       ISNULL(CAST([' + @column_name + '] AS datetime2), ''' + @date_from_char + ''') AS [' + @column_name + ']' + ',' + @new_line;	
									END;
								ELSE
									BEGIN
										IF @column_name = 'Weight'
											BEGIN
												SET @sql = @sql + '       ISNULL([' + @column_name + '], 1.0) AS [' + @column_name + '],' + @new_line;
											END;
										ELSE
											SET @sql = @sql + '       [' + @column_name + '],' + @new_line;
									END;

								FETCH NEXT FROM cColumns
								INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							END;
							CLOSE cColumns;

							SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-LEN(@new_line)) + @new_line;
							SET @sql = @sql + '  FROM ' + @source_table_name + @new_line;
							SET @sql = @sql + ' WHERE [' + @partitioning_column + '] >= ''' + @date_from_char + '''' + @new_line;
							SET @sql = @sql + '   AND [' + @partitioning_column + '] < ''' + @date_to_char + '''' + @new_line;
							SET @sql = @sql + ')' + @new_line;

							/* use insert into for columnstore tables */
							IF @is_clustered_columnstore = 1
								BEGIN
									SET @sql = @sql + 'INSERT INTO ' + @stg_tab_name + @new_line;
								END;

							SET @sql = @sql + 'SELECT ' + @new_line;
							/******************************************/

							OPEN cColumns;
							FETCH NEXT FROM cColumns
							INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							WHILE @@FETCH_STATUS = 0
							BEGIN		
								IF @is_grouping_column = 1
									BEGIN
										SET @grouping_columns = @grouping_columns + '[' + @column_name + '], '
									END;

									SET @sql = @sql + '       [' + @column_name + '],' + @new_line;

								FETCH NEXT FROM cColumns
								INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							END;
							CLOSE cColumns;
	
							SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-LEN(@new_line)) + @new_line;

							/* use select into for standard tables */
							IF @is_clustered_columnstore != 1
								BEGIN
									SET @sql = @sql + '  INTO ' + @stg_tab_name + @new_line;
								END;
							/****************************************/

							SET @sql = @sql + '  FROM _Detail ' + @new_line;						

							/* create stg table */
							--PRINT @sql;
							EXEC sp_executesql @sql;

							/* add indexes */
							/* add check constraint */
							SET @sql = 'ALTER TABLE ' + @stg_tab_name + ' WITH CHECK ADD CONSTRAINT CHK_' + @stg_tab_name + ' CHECK ([' + @partitioning_column + '] >= ''' + @date_from_char + ''' AND [' + @partitioning_column + '] < ''' + @date_to_char + ''');';		

							/* add indexes as on target table except CCSI */
							SELECT @sql = ISNULL(@sql, '') +  CASE [si].[is_primary_key] WHEN 1 THEN
										N'ALTER TABLE ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(@stg_tab_name) + N' ADD CONSTRAINT ' + QUOTENAME('PK_'+ @stg_tab_name) + N' PRIMARY KEY ' +
											CASE WHEN si.index_id > 1 THEN N'NON' ELSE N'' END + N'CLUSTERED '
										ELSE N'CREATE ' + 
											CASE WHEN [si].[is_unique] = 1 then N'UNIQUE ' ELSE N'' END +
											CASE WHEN si.index_id > 1 THEN N'NON' ELSE N'' END + N'CLUSTERED ' + (CASE WHEN si.[type] IN (4, 5) THEN 'COLUMNSTORE ' ELSE '' END) +
											N'INDEX ' + QUOTENAME(si.name) + N' ON ' + QUOTENAME(sc.name) + N'.' + QUOTENAME(@stg_tab_name) + N' '
									END +
									/* key def */ (CASE WHEN si.[type] IN (0, 1, 2) THEN N'(' + [keys].[key_definition] + N')' ELSE '' END) +
									/* includes */ (CASE WHEN si.[type] IN (0, 1, 2) THEN CASE WHEN [includes].[include_definition] IS NOT NULL THEN 
														N' INCLUDE (' + [includes].[include_definition] + N')'
														ELSE N''
													END ELSE '' END) +
									/* ON where? filegroup? partition scheme? */
									N' ON ' + @filegroup
									+ N';'
							  FROM sys.indexes si
							  INNER JOIN sys.tables t 
									  ON si.[object_id] = t.[object_id]
							  INNER JOIN sys.schemas sc 
									  ON t.[schema_id] = sc.[schema_id]
							  OUTER APPLY (SELECT STUFF ((
												SELECT N', ' + QUOTENAME([c].[name]) + CASE [ic].[is_descending_key] WHEN 1 THEN N' DESC' ELSE N'' END 
												  FROM sys.index_columns AS ic 
												  INNER JOIN sys.columns AS c 
														  ON ic.column_id = c.column_id 
														 AND ic.[object_id] = c.[object_id]
												 WHERE ic.[object_id] = si.[object_id]
												   AND [ic].[index_id] = si.index_id
												   AND [ic].[key_ordinal] > 0
												ORDER BY [ic].[key_ordinal]
												FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'),1,2,'')
										  ) AS keys(key_definition)
							  OUTER APPLY (SELECT STUFF ((
												SELECT N', ' + QUOTENAME([c].[name])
												  FROM sys.index_columns AS ic 
												  INNER JOIN sys.columns AS c 
														  ON ic.column_id = c.column_id 
														 AND ic.[object_id] = c.[object_id]
												 WHERE ic.[object_id] = si.[object_id]
												   AND [ic].[index_id] = si.index_id
												   AND ([ic].[is_included_column] = 1
													OR [ic].[key_ordinal] = 0)
												ORDER BY [c].[name]
												FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'),1,2,'')
										  ) AS includes(include_definition)
							 WHERE si.type IN (1, 2)
							   AND t.name = @target_table_name;

							IF @sql != ''
								BEGIN
									--PRINT @sql;									
									EXEC sp_executesql @sql;									
								END;

							/* switch data from stg table into partitioned table  */
							SET @sql = 'ALTER TABLE ' + @stg_tab_name + '
											SWITCH
											TO ' + @target_table_name + ' PARTITION ' + CAST(@partition_number AS NVARCHAR(16)) +
							IIF (@is_alteranyconnection_granted = 1,
									@new_line +
											'WITH (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS))',
											'')
							--PRINT @sql;
							EXEC sp_executesql @sql;

							/* drop stage table */
							SET @sql = 'DROP TABLE ' + @stg_tab_name;
							--PRINT @sql;
							EXEC sp_executesql @sql;				
						END;
					/* else direct INSERT SELECT into part table */
					ELSE
						BEGIN
							SET @sql = 'INSERT INTO ' + @target_table_name + @new_line +
									   'SELECT' + @new_line;

							OPEN cColumns;
							FETCH NEXT FROM cColumns
							INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							WHILE @@FETCH_STATUS = 0
							BEGIN		
								IF @is_grouping_column = 1
									BEGIN
										SET @grouping_columns = @grouping_columns + 'src.[' + @column_name + '], ' + @new_line;
									END;

									SET @sql = @sql + '       src.[' + @column_name + '],' + @new_line;

								FETCH NEXT FROM cColumns
								INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
							END;
							CLOSE cColumns;
	
							SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-LEN(@new_line)) + @new_line;				           
							SET @sql = @sql + '  FROM ' + @source_table_name + ' src' + @new_line;
							/* JOIN target table and filter out all already existing records to avoid duplicates */
							SET @sql = @sql + '  LEFT JOIN ' + @target_table_name + ' trgt' + @new_line;
							/* construct ON clause */
							SELECT @on_cols_sql = @on_cols_sql + IIF(@on_cols_sql = '', '         ON src.[', '        AND src.[') + tsc.ColumnName + '] = trgt.[' + tsc.ColumnName + ']' + @new_line
							  FROM dbm_TimeSeriesConfig tsc
							 WHERE tsc.IsNaturalKey = 1
							   AND tsc.TableName = @tab_name;
							SET @sql = @sql + @on_cols_sql;
							SET @sql = @sql + ' WHERE src.[' + @partitioning_column + '] >= ''' + @date_from_char + ''' AND src.[' + @partitioning_column + '] < ''' + @date_to_char + '''' + @new_line;						
							/* add new filtering clause to avoid duplicates */
							SET @sql = @sql + '   AND trgt.[' + @partitioning_column + '] IS NULL;'
							--PRINT @sql;
							EXEC sp_executesql @sql;
						END;

					/* delete data from cur table */
					SET @sql = 'DELETE FROM ' + @source_table_name + ' WHERE [' + @partitioning_column + '] >= ''' + @date_from_char + ''' AND [' + @partitioning_column + '] < ''' + @date_to_char + '''';
					--PRINT @sql;
					EXEC sp_executesql @sql;

					COMMIT TRANSACTION;
				END TRY
				BEGIN CATCH
					ROLLBACK TRANSACTION;	
					SELECT @error_message = OBJECT_NAME(@@PROCID) + ': ' + ERROR_MESSAGE() + ' ' + @sql, @error_severity = ERROR_SEVERITY(), @error_state = ERROR_STATE();
					INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
					RAISERROR (@error_message, @error_severity, @error_state) WITH NOWAIT;
					/* release lock */
					EXEC sp_releaseapplock @Resource = @source_table_name, @DbPrincipal = 'public', @LockOwner = 'Session';  
					RETURN;
				END CATCH;

				FETCH NEXT FROM cDates
				INTO @processing_date; 
			END;

			CLOSE cDates;
			DEALLOCATE cDates;	
			/* column definitions are same for all dates / so deallocate this at the end */
			DEALLOCATE cColumns;
			/* release lock */
			EXEC sp_releaseapplock @Resource = @source_table_name, @DbPrincipal = 'public', @LockOwner = 'Session';  
		END;
	ELSE 
		BEGIN
			SELECT @error_message = OBJECT_NAME(@@PROCID) + ': Procedure is already running, aborting this execution from hostname: ' + HOST_NAME() + ' under user: ' + SUSER_SNAME() + '.';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 1, 10) WITH NOWAIT;
			RETURN;
		END;
END;
