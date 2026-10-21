IF EXISTS (SELECT [name] FROM sys.procedures WHERE [name] = N'dbm_AggregateTimeSerie_part')
DROP PROCEDURE dbm_AggregateTimeSerie_part;
GO

CREATE PROCEDURE [dbo].[dbm_AggregateTimeSerie_part]
/************************/
/* version 2025-03-13/1 */
/*          BD          */
/************************/
(
 @tab_name NVARCHAR(80),
 @granularity TINYINT,
 @next_aggregation_ready BIT OUTPUT,
 @date DATE OUTPUT,
 @get_dates_from_metadata BIT = 0,
 @reorganize_new_partitions BIT = 1
)
AS
DECLARE @date_from SMALLDATETIME;
DECLARE @date_to SMALLDATETIME;
DECLARE @current_date SMALLDATETIME;
DECLARE @target_partition_scheme NVARCHAR(128);
DECLARE @target_partition_function NVARCHAR(128);
DECLARE @source_partition_scheme NVARCHAR(128);
DECLARE @source_partition_function NVARCHAR(128);
DECLARE @error_message VARCHAR(MAX);
DECLARE @error_severity INT;
DECLARE @error_state INT;
DECLARE @column_name NVARCHAR(64),
        @data_type NVARCHAR(32),
        @aggregate_function NVARCHAR(256),
        @is_grouping_column BIT,
        @is_natural_key BIT,
        @is_nullable BIT,
        @is_partitioning_column BIT,
		@is_derived_metric BIT,
		@is_ranked_metric BIT;
DECLARE @grouping_columns NVARCHAR(1024) = '';
DECLARE @sql NVARCHAR(MAX);
DECLARE @stg_tab_name NVARCHAR(96);
DECLARE @source_tab_name NVARCHAR(96);
DECLARE @target_tab_name NVARCHAR(96);
DECLARE @target_retention SMALLINT;
DECLARE @source_retention SMALLINT;
DECLARE @lower_grain_retention SMALLINT;
DECLARE @partitioning_column NVARCHAR(64);
DECLARE @min_source_day DATE;
DECLARE @max_source_day DATE;
DECLARE @next_source_day DATE;
DECLARE @max_target_day DATE;
DECLARE @min_target_day DATE;
DECLARE @min_target_part_date DATE;
DECLARE @date_to_char NVARCHAR(16);
DECLARE @date_from_char NVARCHAR(16);
DECLARE @min_target_retention DATE;
DECLARE @min_target_retention_char NVARCHAR(16);
DECLARE @min_source_retention DATE;
DECLARE @min_source_retention_char NVARCHAR(16);
DECLARE @is_clustered_columnstore BIT;
DECLARE @target_partition_number INT;
DECLARE @source_partition_number INT;
DECLARE @granularity_string NVARCHAR(8);
DECLARE @key_columns NVARCHAR(1024) = '';
DECLARE @date_to_truncate DATE;
DECLARE @filegroup NVARCHAR(64);
DECLARE @is_alteranyconnection_granted BIT;
DECLARE @processing_day DATE;
DECLARE @last_source_day_to_truncate DATE;
DECLARE @iter INT;
DECLARE @merge_date SMALLDATETIME;
DECLARE @exec_data_processing BIT = 1;
DECLARE @table_with_derived_metric BIT = 0;

SET LANGUAGE English;

BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET IMPLICIT_TRANSACTIONS OFF;

	SET @current_date = @date;

	SELECT @is_alteranyconnection_granted = COUNT(1)
	  FROM fn_my_permissions(NULL, 'SERVER')
	 WHERE permission_name = 'ALTER ANY CONNECTION'
	;

	SELECT TOP 1 @filegroup = [Filegroup]
	  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
	 WHERE tspc.TableName = @tab_name
	   AND tspc.TableType = IIF(@granularity = 2, 'Hourly', 'Daily')
	;

	IF @filegroup IS NULL 
		BEGIN
			SET @filegroup = '[PRIMARY]';
		END;
	ELSE IF SUBSTRING(@filegroup, 1, 1) != '['
		BEGIN
			SET @filegroup = '[' + @filegroup + ']';
		END;

	SET @next_aggregation_ready = 0;

	/* stage/source/target tab names */
	IF @granularity = 2
		--hourly
		BEGIN						
			SET @stg_tab_name = @tab_name + '_Hourly_stg';
			SET @source_tab_name = @tab_name + '_Detail_hist';
			SET @target_tab_name = @tab_name + '_Hourly_hist';
			SET @granularity_string = 'Hourly';
		END;
	ELSE IF @granularity = 3
		--daily
		BEGIN
			SET @stg_tab_name = @tab_name + '_Daily_stg';
			SET @source_tab_name = @tab_name + '_Hourly_hist';
			SET @target_tab_name = @tab_name + '_Daily_hist';
			SET @granularity_string = 'Daily';
		END; 
	ELSE
		--nonsense
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Parameter @granularity = ' + ISNULL(CAST(@granularity AS NVARCHAR(16)), 'NULL')
			                   + ' has unknown value. All parameters: @granularity: ' + ISNULL(CAST(@granularity AS NVARCHAR(16)), 'NULL')
							   + ', @tab_name: ' + @tab_name + ', @filegroup: ' + ISNULL(@filegroup, 'NULL');
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 16, 1) WITH NOWAIT;
			RETURN;
		END;
	
	/* explicit check whether table contains some derived metric */
	SELECT DISTINCT @table_with_derived_metric = cnf.IsDerivedMetric
	  FROM dbm_TimeSeriesConfig cnf WITH (NOLOCK)
	 WHERE cnf.IsDerivedMetric = 1
	   AND cnf.TableName = @tab_name;

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
		   AND t.name = @target_tab_name
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

	/* is partitioned table in columnstore index? */
	SELECT @is_clustered_columnstore = COUNT(i.index_id)
	  FROM sys.tables t WITH(NOLOCK)
	  INNER JOIN sys.indexes i WITH(NOLOCK)
	          ON t.object_id = i.object_id
	 WHERE t.name = @target_tab_name
	   AND i.type = 5;

	/* load available parameters from metadata */	
	/* handle @lower_grain_retention */
	SELECT @lower_grain_retention = tspc.RetentionDays	
	  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
	 WHERE tspc.TableType = CASE WHEN @granularity = 2 THEN 'cur' WHEN @granularity = 3 THEN 'Detail' END
	   AND tspc.TableName = @tab_name;

	/* handle min source retention */
	SELECT @source_retention = tspc.RetentionDays
	  FROM dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
	 WHERE tspc.TableType = CASE WHEN @granularity = 2 THEN 'Detail' WHEN @granularity = 3 THEN 'Hourly' END
	   AND tspc.TableName = @tab_name;

	/* handle min target retention */	
	SELECT @target_retention = tspc.RetentionDays,
		   @partitioning_column = tsc.ColumnName	
	  FROM dbm_TimeSeriesConfig tsc WITH (NOLOCK)
	  INNER JOIN dbm_TimeSerieProcessingConfig tspc WITH (NOLOCK)
			  ON tsc.TableName = tspc.TableName
	 WHERE tspc.TableType = CASE WHEN @granularity = 2 THEN 'Hourly' WHEN @granularity = 3 THEN 'Daily' END
	   AND tsc.TableName = @tab_name
	   AND tsc.IsPartitioningColumn = 1;

	IF (@target_retention <= @source_retention OR @source_retention <= @lower_grain_retention)
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Retention settings in dbm_TimeSerieProcessingConfig table are wrong! Sequence of retention periods for ' + @tab_name + ' must be growing from "cur" to "Hourly". Aggregation aborted!';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 16, 1) WITH NOWAIT;
			RETURN;
		END;

	/* when @partitioning_column is null then exit sp = missing metadata */	
	IF @target_retention IS NULL OR @source_retention IS NULL
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Retention settings for ' + @tab_name + '_* tables not defined! Change their definition in dbm_TimeSerieProcessingConfig table.';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 16, 1) WITH NOWAIT;
			RETURN;
		END;

	/* when @partitioning_column is null then exit sp = missing metadata */	
	IF @partitioning_column IS NULL 
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Partitioning column for ' + @tab_name + '_* tables is not defined! Change their definition in dbm_TimeSeriesConfig table.';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 16, 1) WITH NOWAIT;
			RETURN;
		END;

	/* source and target days */
	IF @get_dates_from_metadata = 0
		BEGIN
			SET @sql = 'SELECT @min_source_day = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MIN([' + @partitioning_column + '])), ''20000101''), @max_source_day = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MAX([' + @partitioning_column + '])), ''20000101'') FROM ' + @source_tab_name + ' WITH (NOLOCK)';
			--PRINT @sql;
			EXEC sp_executesql @sql, N'@min_source_day DATETIME2 OUTPUT, @max_source_day DATETIME2 OUTPUT', @min_source_day = @min_source_day OUTPUT, @max_source_day = @max_source_day OUTPUT;
		END;
	ELSE
		BEGIN
			--partitioning RIGHT so we have to substract 1 DAY from all range values!
			SELECT @min_source_day = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE)),
				   @max_source_day = DATEADD(DAY, -1, CAST(MAX(prv.value) AS DATE))
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
			 WHERE p.object_id = OBJECT_ID(@source_tab_name)
			   AND ind.type IN (0,1,5)
			   AND p.rows > 0
			;
		END;

	IF @get_dates_from_metadata = 0
		BEGIN
			SET @sql = 'SELECT @max_target_day = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MAX([' + @partitioning_column + '])), ''20000101''), @min_target_day = DATEADD(DAY, DATEDIFF(DAY, ''20000101'', MIN([' + @partitioning_column + '])), ''20000101'') FROM ' + @target_tab_name + ' WITH (NOLOCK)';
			--PRINT @sql;
			EXEC sp_executesql @sql, N'@max_target_day DATETIME2 OUTPUT, @min_target_day DATETIME2 OUTPUT', @max_target_day = @max_target_day OUTPUT, @min_target_day = @min_target_day OUTPUT;	
		END;
	ELSE
		BEGIN
			--partitioning RIGHT so we have to substract 1 DAY from all range values!
			SELECT @max_target_day = DATEADD(DAY, -1, CAST(MAX(prv.value) AS DATE)),
                   @min_target_day = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE))
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
			 WHERE p.object_id = OBJECT_ID(@target_tab_name)
			   AND ind.type IN (0,1,5)
			   AND p.rows > 0
			;
		END;

	/* get min _daily partition (even when it is empty) */
	SELECT @min_target_part_date = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE))
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
	 WHERE p.object_id = OBJECT_ID(@target_tab_name)
	   AND ind.type IN (0,1,5)
	;	

	/* get @date_from date */
	IF (@max_target_day IS NULL OR @min_source_day > DATEADD(DAY, 1 ,@max_target_day))
		SET @date_from = @min_source_day;
	ELSE
		BEGIN
			IF @get_dates_from_metadata = 0
				BEGIN
					SET @sql = 'SELECT TOP 1 @next_source_day = CAST(CAST([' + @partitioning_column + '] AS DATE) AS DATETIME2) FROM ' + @source_tab_name + ' WITH (NOLOCK) WHERE CAST(CAST([' + @partitioning_column + '] AS DATE) AS DATETIME2) >= CAST(DATEADD(DAY, 1, @max_target_day) AS DATETIME2)';
					--PRINT @sql;
					EXEC sp_executesql @sql, N'@next_source_day DATETIME2 OUTPUT, @max_target_day DATE', @next_source_day = @next_source_day OUTPUT, @max_target_day = @max_target_day;	
				END;
			ELSE
				BEGIN
					/* partitioning RIGHT so we have to substract 1 DAY from all range values! */
					SELECT @next_source_day = DATEADD(DAY, -1, CAST(prv.value AS DATE))
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
					 WHERE p.object_id = OBJECT_ID(@source_tab_name)
					   AND ind.type IN (0,1,5)
					   AND p.rows > 0
					   AND DATEADD(DAY, -1, CAST(prv.value AS DATE)) > @max_target_day
					;				
				END;	
			SET @date_from = ISNULL(@next_source_day, @max_target_day);
		END;

	/* date for table name */	
	SET @date_to = DATEADD(DAY, 1/*@days_in_part*/, @date_from);
	SET @date_from_char = CONVERT(NVARCHAR, @date_from, 112);
	SET @date_to_char = CONVERT(NVARCHAR, @date_to, 112);
	SET @min_source_retention = DATEADD(DAY, -@source_retention, @date);
	SET @min_source_retention_char = CONVERT(NVARCHAR, @min_source_retention, 112);	
	SET @min_target_retention = DATEADD(DAY, -@target_retention, @date);
	SET @min_target_retention_char = CONVERT(NVARCHAR, @min_target_retention, 112);
	SET @date_to_truncate = CAST(DATEADD(DAY, -1-@target_retention, @date) AS DATE);
	SET @date_to_truncate = IIF(@date_to_truncate > @max_target_day, @max_target_day, @date_to_truncate);-- -dateadd day 1 maxtargetday -- nemaze to posledni partition.

	SET @processing_day = @date_from;
	/* cannot truncate non-existing day so adding @max_source_day_instead */
	SET @last_source_day_to_truncate = IIF(@min_source_retention > @max_source_day, @max_source_day, @min_source_retention);
	/*
	PRINT '************************************************************';
	PRINT '@date: ' + CAST(@date AS NVARCHAR(32));
	PRINT '@current_date: ' + CAST(@current_date AS NVARCHAR(32));
	PRINT '@source_retention: ' + CAST(@source_retention AS NVARCHAR(6));
	PRINT '@target_retention: ' + CAST(@target_retention AS NVARCHAR(6));
    PRINT '@next_source_day: ' + CAST(@next_source_day AS NVARCHAR(32));
	PRINT '@date_from: ' + @date_from_char;
	PRINT '@date_to: ' + @date_to_char;
	PRINT '@min_target_retention: ' + @min_target_retention_char;
	PRINT '@min_source_retention: ' + @min_source_retention_char;
	PRINT '@max_target_day: ' + CAST(@max_target_day AS NVARCHAR(32));
	PRINT '@max_source_day: ' + CAST(@max_source_day AS NVARCHAR(32));
	PRINT '@min_source_day: ' + CAST(@min_source_day AS NVARCHAR(32));
	PRINT '@min_target_day: ' + CAST(@min_target_day AS NVARCHAR(32));
	PRINT '@date_to_truncate: ' + CAST(@date_to_truncate AS NVARCHAR(32));	
	PRINT '@processing_day: ' + CAST(@processing_day AS NVARCHAR(32));	
	PRINT '@last_source_day_to_truncate: ' + CAST(@last_source_day_to_truncate AS NVARCHAR(32));	
	PRINT '@min_target_part_date: ' + CAST(@min_target_part_date AS NVARCHAR(32));
	*/

	/* target partition function and scheme */
	SELECT @target_partition_scheme = ps.name,
		   @target_partition_function = pf.name
	  FROM sys.partition_schemes ps WITH (NOLOCK)
	  INNER JOIN sys.partition_functions pf WITH (NOLOCK)
			  ON pf.function_id = ps.function_id
	  INNER JOIN sys.data_spaces ds WITH (NOLOCK)
			  ON ds.data_space_id = ps.data_space_id
	  INNER JOIN sys.indexes i WITH (NOLOCK)
			  ON i.data_space_id = ps.data_space_id
	  INNER JOIN sys.tables t WITH (NOLOCK)
			  ON t.object_id = i.object_id
	 WHERE t.name = @target_tab_name
	   AND i.type IN (0,1,5)
	;

	/* source partition function and scheme */
	SELECT @source_partition_scheme = ps.name,
		   @source_partition_function = pf.name
	  FROM sys.partition_schemes ps WITH (NOLOCK)
	  INNER JOIN sys.partition_functions pf WITH (NOLOCK)
			  ON pf.function_id = ps.function_id
	  INNER JOIN sys.data_spaces ds WITH (NOLOCK)
			  ON ds.data_space_id = ps.data_space_id
	  INNER JOIN sys.indexes i WITH (NOLOCK)
			  ON i.data_space_id = ps.data_space_id
	  INNER JOIN sys.tables t WITH (NOLOCK)
			  ON t.object_id = i.object_id
	 WHERE t.name = @source_tab_name
	   AND i.type IN (0,1,5)
	;

	/* get source_partition number to truncate */
	/* because we use RANGE RIGHT proper partition range in this table is @date_from+1 day */
	/* or @date_to if we use 1 day partitions only! */
	SELECT @source_partition_number = p.partition_number
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
	 WHERE p.object_id = OBJECT_ID(@source_tab_name)
	   AND ind.type IN (0,1,5)
	   AND prv.value = CAST(@date_to AS DATETIME2)
	;

	/* do not process data newer than @date */
	IF @date_from > @date
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Processing of data newer than passed @date parameter from ' + @source_tab_name + ' is forbidden!';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 10, 1) WITH NOWAIT;
			SET @next_aggregation_ready = 0;
			RETURN;
		END;

	/* when there are no source data then exit sp */
	IF @min_source_day IS NULL OR @max_target_day >= @max_source_day
		BEGIN
			/* even when there are no data to aggregate, truncate _Daily_hist tables */
			GOTO Truncate_Daily;
		END;

	/* when there are just fresh data then exit sp */
	IF @date_from >= @min_source_retention
	--@min_source_day > DATEADD(DAY, -1, @current_date)
		BEGIN
			/* even when there are no data to aggregate, truncate _Daily_hist tables */
			GOTO Truncate_Daily;
		END;

	/* when the source data are not complete for full target partition exit sp */
	IF @max_target_day >= @min_source_retention OR @date_from > @min_source_retention
		BEGIN
			SET @error_message = OBJECT_NAME(@@PROCID) + ': Data in ' + @source_tab_name + ' are not sufficient for processing of this aggregation.';
			INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
			RAISERROR (@error_message, 10, 1) WITH NOWAIT;
			/* even when there are no data to aggregate, truncate _Daily_hist tables */
			GOTO Truncate_Daily;
		END;

	/* assign OUTPUT parameter value */
	SET @date = @date_to;

	BEGIN TRY
		BEGIN TRANSACTION
			IF @exec_data_processing = 1
				BEGIN
					/* create stage table for ccsi */
					IF @is_clustered_columnstore = 1
						BEGIN
							SET @sql = 'CREATE TABLE ' + @stg_tab_name + CHAR(13) + '(' + CHAR(13);

							OPEN cColumns;
							FETCH NEXT FROM cColumns
							INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
							WHILE @@FETCH_STATUS = 0
							BEGIN		
								IF @is_partitioning_column = 1
									BEGIN
										SET @partitioning_column = @column_name;
									END;

								IF @is_derived_metric = 1 AND @granularity > 1
									BEGIN
										IF @is_nullable = 1
											BEGIN
												SET @sql = @sql + '[Min' + @column_name + '] ' + @data_type + ' ' + 'NULL,' + CHAR(13);
												SET @sql = @sql + '[Max' + @column_name + '] ' + @data_type + ' ' + 'NULL,' + CHAR(13);
												SET @sql = @sql + '[' + dbo.InitialCap(@aggregate_function) + @column_name + '] ' + @data_type + ' ' + 'NULL,' + CHAR(13);
											END;
										ELSE
											BEGIN
												SET @sql = @sql + '[Min' + @column_name + '] ' + @data_type + ' ' + 'NOT NULL,' + CHAR(13);
												SET @sql = @sql + '[Max' + @column_name + '] ' + @data_type + ' ' + 'NOT NULL,' + CHAR(13);
												SET @sql = @sql + '[' + dbo.InitialCap(@aggregate_function) + @column_name + '] ' + @data_type + ' ' + 'NOT NULL,' + CHAR(13);
											END;					
									END;
								ELSE
									BEGIN
										IF @is_nullable = 1
											BEGIN
												SET @sql = @sql + '[' + @column_name + '] ' + @data_type + ' ' + 'NULL,' + CHAR(13);
											END;
										ELSE
											BEGIN
												SET @sql = @sql + '[' + @column_name + '] ' + @data_type + ' ' + 'NOT NULL,' + CHAR(13);
											END;
									END;

								FETCH NEXT FROM cColumns
								INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
							END;
							CLOSE cColumns;

							SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-1) + CHAR(13);
							SET @sql = @sql + ') ON ' + @filegroup;
							--PRINT @sql;
							EXEC sp_executesql @sql;

							/* add clustered columnstore index */
							SET @sql = 'CREATE CLUSTERED COLUMNSTORE INDEX [CCSI_' + @stg_tab_name + '] ON [' + @stg_tab_name + '] ON ' + @filegroup;
							--PRINT @sql;
							EXEC sp_executesql @sql;
							/************/
						END;
			
					/*********************/
					/* create insert sql */
					SET @sql = 'WITH time_recalc' + CHAR(13) + 'AS' + CHAR(13) + '(' + CHAR(13) + 'SELECT' + CHAR(13);
					/* CTE with time recalculation */
					OPEN cColumns;
					FETCH NEXT FROM cColumns
					INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
					WHILE @@FETCH_STATUS = 0
					BEGIN		
						IF @is_natural_key = 1
							BEGIN
								SET @key_columns = @key_columns + '[' + @column_name + '], ';
							END;

						IF @is_partitioning_column = 1
							BEGIN
								SET @partitioning_column = @column_name;
								IF @granularity = 2
									--hourly
									BEGIN					
										SET @sql = @sql + '       ISNULL(CAST(DATEADD(HOUR, DATEDIFF(HOUR, ''20000101'', [' + @column_name + ']), ''20000101'') AS datetime2), ''' + @date_from_char + ''') AS [' + @column_name + ']' + ',' + CHAR(13);	
										IF @is_ranked_metric = 1
											BEGIN
												SET @sql = @sql + '       [' + @column_name + '] AS orig_date_time,' + CHAR(13);
											END;
									END;
								ELSE IF @granularity = 3
									--daily
									BEGIN
										SET @sql = @sql + '       ISNULL(CAST(DATEADD(DAY, DATEDIFF(DAY, ''20000101'', [' + @column_name + ']), ''20000101'') AS datetime2), ''' + @date_from_char + ''') AS [' + @column_name + ']' + ',' + CHAR(13);	
										IF @is_ranked_metric = 1
											BEGIN
												SET @sql = @sql + '       [' + @column_name + '] AS orig_date_time,' + CHAR(13);
											END;
									END; 
								ELSE
									RETURN;
							END;
						ELSE
							BEGIN
								/* create columns for derived metrics when aggregating _hourly to _daily */
								IF @is_derived_metric = 1 AND @granularity = 3
									BEGIN
										SET @sql = @sql + '       [Min' + @column_name + '],' + CHAR(13);
										SET @sql = @sql + '       [Max' + @column_name + '],' + CHAR(13);
										SET @sql = @sql + '       [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
									END;
								/* standard metric */
								ELSE
									BEGIN
										SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);						
									END;						
							END;

						FETCH NEXT FROM cColumns
						INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
					END;
					CLOSE cColumns;

					/* remove last comma from key_columns */
					SET @key_columns = SUBSTRING(@key_columns, 0, LEN(@key_columns));
					SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-1) + CHAR(13);
					SET @sql = @sql + '  FROM ' + @source_tab_name + CHAR(13);
					SET @sql = @sql + ' WHERE [' + @partitioning_column + '] >= ''' + @date_from_char + '''' + CHAR(13);
					SET @sql = @sql + '   AND [' + @partitioning_column + '] < ''' + @date_to_char + '''' + CHAR(13);
					SET @sql = @sql + '),' + CHAR(13);
					SET @sql = @sql + 'agg_data' + CHAR(13) + 'AS' + CHAR(13) + '(' + CHAR(13) + 'SELECT' + CHAR(13);

					/* CTE with derived columns computation */
					OPEN cColumns;
					FETCH NEXT FROM cColumns
					INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
					WHILE @@FETCH_STATUS = 0
					BEGIN		
						IF @is_grouping_column = 1
							BEGIN
								SET @grouping_columns = @grouping_columns + '[' + @column_name + '], '
							END;

						IF @is_natural_key != 1 AND @is_partitioning_column = 0 AND @is_grouping_column != 1
							BEGIN
								/* create columns for derived metrics */
								IF @is_derived_metric = 1
									BEGIN
										IF @granularity = 2
											IF @is_ranked_metric != 1
												/* take data from _detail table where there are no derived columns! */
												BEGIN
													SET @sql = @sql + '       CAST(MIN([' + @column_name + ']) AS ' + @data_type + ') [Min' + @column_name + '],' + CHAR(13);
													SET @sql = @sql + '       CAST(MAX([' + @column_name + ']) AS ' + @data_type + ') [Max' + @column_name + '],' + CHAR(13);
													IF @aggregate_function = 'AVG'
														/* use weighted average */
														BEGIN
															SET @sql = @sql + '       CAST((SUM(['+ @column_name + '] * CAST([Weight] AS DECIMAL)) / (SUM([Weight]))) AS ' + @data_type + ') [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
														END;
													ELSE
														SET @sql = @sql + '       CAST(' + @aggregate_function + '(['+ @column_name + ']) AS ' + @data_type + ') [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
												END;
											ELSE
												/* derived metric & ranked metric - detail */
												BEGIN
													IF @aggregate_function != 'NONE'
														BEGIN
															IF @aggregate_function = 'AVG'														
																/* use weighted average */
																BEGIN																
																	IF @is_nullable = 0
																		BEGIN
																			SET @sql = @sql + '       ISNULL(CAST((MIN([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + '), 1.0) AS [Min' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       ISNULL(CAST((MAX([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + '), 1.0) AS [Max' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       ISNULL(CAST((SUM([' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + '), 1.0) AS [Avg' + @column_name + '],' + CHAR(13);						
																		END;
																	ELSE 
																		BEGIN
																			SET @sql = @sql + '       CAST((MIN([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + ') AS [Min' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       CAST((MAX([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + ') AS [Max' + @column_name + '],' + CHAR(13);	
																			SET @sql = @sql + '       CAST((SUM([' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + ') AS [Avg' + @column_name + '],' + CHAR(13);						
																		END;
																END;
															ELSE
																BEGIN
																	SET @aggregate_function = @aggregate_function + '([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')';
																	IF @is_nullable = 0
																		SET @sql = @sql + '       ISNULL(CAST('+ @aggregate_function + ' AS ' + @data_type + '), 1.0) AS [' + @column_name + '],' + CHAR(13);
																	ELSE 
																		SET @sql = @sql + '       CAST('+ @aggregate_function + ' AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);
																END;
														END;
													ELSE
														SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);														
												END;
										ELSE
											/* data from _hourly table with derived columns */
											IF @is_ranked_metric != 1
												BEGIN
													SET @sql = @sql + '       CAST(MIN([Min' + @column_name + ']) AS ' + @data_type + ') [Min' + @column_name + '],' + CHAR(13);
													SET @sql = @sql + '       CAST(MAX([Max' + @column_name + ']) AS ' + @data_type + ') [Max' + @column_name + '],' + CHAR(13);
													IF @aggregate_function = 'AVG'
														/* use weighted average */
														BEGIN
															SET @sql = @sql + '       CAST((SUM([Avg'+ @column_name + '] * CAST([Weight] AS DECIMAL)) / (SUM([Weight]))) AS ' + @data_type + ') [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
														END;
													ELSE
														SET @sql = @sql + '       CAST(' + @aggregate_function + '([' + dbo.InitialCap(@aggregate_function) + @column_name + ']) AS ' + @data_type + ') [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
												END;
											ELSE
												/* ranked metric with derived columns / hourly+ granularity */
												BEGIN
													IF @aggregate_function != 'NONE'
														BEGIN
															IF @aggregate_function = 'AVG'														
																/* use weighted average */
																BEGIN																
																	IF @is_nullable = 0
																		BEGIN
																			SET @sql = @sql + '       ISNULL(CAST((MIN([Min' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + '), 1.0) AS [Min' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       ISNULL(CAST((MAX([Max' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + '), 1.0) AS [Max' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       ISNULL(CAST((SUM([Avg' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + '), 1.0) AS [Avg' + @column_name + '],' + CHAR(13);						
																		END;
																	ELSE 
																		BEGIN
																			SET @sql = @sql + '       CAST((MIN([Min' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + ') AS [Min' + @column_name + '],' + CHAR(13);						
																			SET @sql = @sql + '       CAST((MAX([Max' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')) AS ' + @data_type + ') AS [Max' + @column_name + '],' + CHAR(13);	
																			SET @sql = @sql + '       CAST((SUM([Avg' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + ') AS [Avg' + @column_name + '],' + CHAR(13);						
																		END;
																END;
															ELSE
																BEGIN
																	SET @aggregate_function = @aggregate_function + '([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')';
																	IF @is_nullable = 0
																		SET @sql = @sql + '       ISNULL(CAST('+ @aggregate_function + ' AS ' + @data_type + '), 1.0) AS [' + @column_name + '],' + CHAR(13);
																	ELSE 
																		SET @sql = @sql + '       CAST('+ @aggregate_function + ' AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);
																END;
														END;
													ELSE
														SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);

												END;
									END;
								/* standard metric */
								ELSE
									BEGIN
										IF @is_ranked_metric = 1
											BEGIN	
												IF @aggregate_function != 'NONE'
													BEGIN
														IF @aggregate_function = 'AVG'
															/* use weighted average */
															BEGIN																
																IF @is_nullable = 0
																	SET @sql = @sql + '       ISNULL(CAST((SUM([' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + '), 1.0) AS [' + @column_name + '],' + CHAR(13);						
																ELSE 
																	SET @sql = @sql + '       CAST((SUM([' + @column_name + '] * CAST([Weight] AS DECIMAL)) OVER (PARTITION BY ' + @key_columns + ') / (SUM([Weight]) OVER (PARTITION BY ' + @key_columns + '))) AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);						
															END;
														ELSE
															BEGIN
																SET @aggregate_function = @aggregate_function + '([' + @column_name + ']) OVER (PARTITION BY ' + @key_columns + ')';
																IF @is_nullable = 0
																	SET @sql = @sql + '       ISNULL(CAST('+ @aggregate_function + ' AS ' + @data_type + '), 1.0) AS [' + @column_name + '],' + CHAR(13);
																ELSE 
																	SET @sql = @sql + '       CAST('+ @aggregate_function + ' AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);
															END;
													END;
												ELSE
													SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);														
											END;
										ELSE
											BEGIN
												IF @aggregate_function = 'AVG'
													/* use weighted average */
													BEGIN
														SET @sql = @sql + '       CAST((SUM([' + @column_name + '] * CAST([Weight] AS DECIMAL)) / (SUM([Weight]))) AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);						
													END;
												ELSE
													BEGIN
														IF @column_name = 'Weight'
															BEGIN
																SET @sql = @sql + '       ISNULL(CAST('+ @aggregate_function + '([' + @column_name + ']) AS ' + @data_type + '), 1.0) AS [' + @column_name + '],' + CHAR(13);
															END;
														ELSE
															SET @sql = @sql + '       CAST('+ @aggregate_function + '([' + @column_name + ']) AS ' + @data_type + ') AS [' + @column_name + '],' + CHAR(13);						
													END;
											END;
									END;
								END;					
						ELSE
							BEGIN
								IF @is_ranked_metric = 1 AND @is_partitioning_column = 1
									BEGIN
										/* decode last and first to rank() over */
										IF @aggregate_function = 'LAST'
											BEGIN
												SET @aggregate_function = 'RANK() OVER (PARTITION BY ' + @key_columns + ' ORDER BY orig_date_time DESC)';
											END;
										ELSE IF @aggregate_function = 'FIRST'
											BEGIN
												SET @aggregate_function = 'RANK() OVER (PARTITION BY ' + @key_columns + ' ORDER BY orig_date_time ASC)';
											END;

										SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);
										SET @sql = @sql + '       ' + @aggregate_function + ' AS rnk,' + CHAR(13);
									END;
								ELSE
									BEGIN
										SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);
									END;
							END;
											
						FETCH NEXT FROM cColumns
						INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
					END;
					CLOSE cColumns;

					SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-1) + CHAR(13);
					SET @sql = @sql + '  FROM time_recalc' + CHAR(13);
					IF @is_ranked_metric != 1
						BEGIN
							SET @sql = @sql + 'GROUP BY ' + SUBSTRING(@grouping_columns, 0, LEN(@grouping_columns)) + CHAR(13);
						END;
					SET @sql = @sql + ')' + CHAR(13);

					/* use insert into for columnstore tables */
					IF @is_clustered_columnstore = 1
						BEGIN
							SET @sql = @sql + 'INSERT INTO ' + @stg_tab_name + CHAR(13);
						END;
					/******************************************/

					SET @sql = @sql + 'SELECT ' + CHAR(13);

					/* final SELECT */
					OPEN cColumns;
					FETCH NEXT FROM cColumns
					INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric; 
					WHILE @@FETCH_STATUS = 0
					BEGIN		
						IF @is_grouping_column = 1
							BEGIN
								SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);
								SET @grouping_columns = @grouping_columns + '[' + @column_name + '], '
							END;
						ELSE
							BEGIN
								/* create columns for derived metrics */
								IF @is_derived_metric = 1
									BEGIN
										SET @sql = @sql + '       [Min' + @column_name + '],' + CHAR(13);
										SET @sql = @sql + '       [Max' + @column_name + '],' + CHAR(13);
										SET @sql = @sql + '       [' + dbo.InitialCap(@aggregate_function) + @column_name + '],' + CHAR(13);
									END;
								/* standard metric */
								ELSE
									BEGIN
										SET @sql = @sql + '       [' + @column_name + '],' + CHAR(13);								
									END;						
							END;

						FETCH NEXT FROM cColumns
						INTO @column_name, @data_type, @aggregate_function, @is_grouping_column, @is_natural_key, @is_nullable, @is_partitioning_column, @is_derived_metric, @is_ranked_metric;
					END;
					CLOSE cColumns;
					DEALLOCATE cColumns;

					SET @sql = SUBSTRING(@sql, 0, LEN(@sql)-1) + CHAR(13);

					/* use select into for standard tables */
					IF @is_clustered_columnstore != 1
						BEGIN
							SET @sql = @sql + '  INTO ' + @stg_tab_name + CHAR(13);
						END;
					/****************************************/

					SET @sql = @sql + '  FROM agg_data ' + CHAR(13);
					IF @is_ranked_metric = 1
						BEGIN
							SET @sql = @sql + ' WHERE rnk = 1' + CHAR(13);
						END;

					/* create stg_table with data for a new partition */
					--PRINT @sql;		    
					EXEC sp_executesql @sql;		

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
					   AND t.name = @target_tab_name;

					IF @sql != ''
						BEGIN
							--PRINT @sql;
							EXEC sp_executesql @sql;
						END;


					/* get target_partition number to switch data in */
					SET @sql = 'SELECT @target_partition_number = $PARTITION.' + @target_partition_function + '(''' + @date_from_char + ''')';
					--PRINT @sql;
					EXEC sp_executesql @sql, N'@target_partition_number INT OUTPUT', @target_partition_number = @target_partition_number OUTPUT;

					/* switch data from stg table into partitioned table  */
					SET @sql = 'ALTER TABLE ' + @stg_tab_name + '
									SWITCH
									TO ' + @target_tab_name + ' PARTITION ' + CAST(@target_partition_number AS NVARCHAR(16)) +
					IIF (@is_alteranyconnection_granted = 1,
						 CHAR(13) + CHAR(10) + ' WITH (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS))',
						 '');
					--PRINT @sql;
					EXEC sp_executesql @sql;	

					/* drop stage table! */
					SET @sql = 'DROP TABLE ' + @stg_tab_name;
					--PRINT @sql;
					EXEC sp_executesql @sql;
				END;

				/* truncate source partition and merge range */
				SET @sql = 'TRUNCATE TABLE ' + @source_tab_name + ' WITH (PARTITIONS (' + CAST(@source_partition_number AS NVARCHAR(6)) + '))';		
				--PRINT @sql;
				EXEC sp_executesql @sql;

				/* merge partition only if it is not the first one in the table! */
				IF @source_partition_number > 1
					BEGIN
						/* double check previous partitions are empty as well! */	
						/* this fixes overlapping data after migration */					
						DECLARE @previous_partition_number INT;
						SET @previous_partition_number = @source_partition_number - 1;
						WHILE @previous_partition_number != 0
							BEGIN
								SET @sql = 'TRUNCATE TABLE ' + @source_tab_name + ' WITH (PARTITIONS (' + CAST(@previous_partition_number AS NVARCHAR(6)) + '))';		
								--PRINT @sql;
								EXEC sp_executesql @sql;	

								SET @previous_partition_number = @previous_partition_number - 1;
							END;

						/* because we use RANGE RIGHT proper merge range base is @date_from+1 */
						/* or @date_to if we use 1 day partitions only!					      */
						SET @iter = 1;
						SET @merge_date = DATEADD(DAY, -(@source_partition_number-1) , @date_to);

						WHILE @iter < (@source_partition_number)
							BEGIN
								SET @sql = 'ALTER PARTITION FUNCTION ' + @source_partition_function + '() MERGE RANGE (@merge_date)';
								--PRINT @sql;
								EXEC sp_executesql @sql, N'@merge_date DATETIME2', @merge_date = @merge_date;
								--PRINT @sql;				
								SET @iter = @iter + 1;
								SET @merge_date = DATEADD(DAY, 1, @merge_date);
							END;			
					END;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		SELECT @error_message = OBJECT_NAME(@@PROCID) + ': ' + 'XACT_STATE=' + CAST(XACT_STATE() AS VARCHAR) + ERROR_MESSAGE() + ', ' + @sql, @error_severity = ERROR_SEVERITY(), @error_state = ERROR_STATE();

		IF (XACT_STATE()) = -1  
			BEGIN  
				ROLLBACK TRANSACTION;  
			END;  
 
		IF (XACT_STATE()) = 1  
			BEGIN  
				COMMIT TRANSACTION;     
			END;  		
		INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
		RAISERROR (@error_message, @error_severity, @error_state) WITH NOWAIT;
		RETURN;
	END CATCH;	

	/* even when there are no hourly data to aggregate */
	/* label for GOTO */
	Truncate_Daily:

	BEGIN TRY
		BEGIN TRANSACTION
			IF @reorganize_new_partitions <> 0
				BEGIN
					/* force columnstore compression */			
					IF @is_clustered_columnstore = 1
						BEGIN
							SET @sql = 'ALTER INDEX [CCSI_' + @target_tab_name + '] ON [' + @target_tab_name + '] REORGANIZE PARTITION = ' + CAST(@target_partition_number AS NVARCHAR(16)) + ' WITH (COMPRESS_ALL_ROW_GROUPS = ON)';
							--PRINT @sql;
							EXEC sp_executesql @sql;
						END;	
				END;	

			/* handle target retention periods */
			-- just for _daily data (3)			
			IF @granularity = 3 AND @date_to_truncate >= @min_target_part_date AND @date_to_truncate <= @processing_day AND @max_target_day IS NOT NULL
				BEGIN
					/* get rid of very old empty partitions if they exist due to the long system shutdown */
					--PRINT @target_partition_function;
					--PRINT '@min_target_part_date: ' + CAST(@min_target_part_date AS NVARCHAR(32));
					--PRINT '@min_source_day: ' + CAST(@min_source_day AS NVARCHAR(32));
					SET @sql = NULL;
					SELECT @sql = ISNULL(@sql, '') + 'ALTER PARTITION FUNCTION ' + @target_partition_function + '() MERGE RANGE (CAST(''' + CONVERT(NVARCHAR, prv.value, 112) + ''' AS DATETIME2));' + CHAR(13)
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
					 WHERE p.object_id = OBJECT_ID(@target_tab_name)
					  AND ind.type IN (0,1,5)
					  AND prv.value IS NOT NULL
					  AND prv.value < CAST(IIF(@min_target_day IS NULL, @min_source_day, @min_target_day) AS DATETIME2)
					ORDER BY prv.value
					;				
					--PRINT @sql;	
					IF (@sql IS NOT NULL OR @sql != '')	EXEC sp_executesql @sql;

					/* return proper min partition */
					SELECT @min_target_part_date = DATEADD(DAY, -1, CAST(MIN(prv.value) AS DATE))
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
					 WHERE p.object_id = OBJECT_ID(@target_tab_name)
					   AND ind.type IN (0,1,5)
					;	
					--PRINT '@min_target_part_date: ' + CAST(@min_target_part_date AS NVARCHAR(32));

					/* truncate partitions with data */
					DECLARE @truncate_partition_number INT;
					DECLARE @min_truncate_day DATE = @min_target_day;					
					WHILE @min_truncate_day <= @date_to_truncate
						BEGIN							
							SET @sql = 'SELECT @truncate_partition_number = $PARTITION.' + @target_partition_function + '(@min_truncate_day)';
							--PRINT @sql;
							EXEC sp_executesql @sql, N'@truncate_partition_number INT OUTPUT, @min_truncate_day DATETIME2', @truncate_partition_number = @truncate_partition_number OUTPUT, @min_truncate_day = @min_truncate_day;
							--PRINT @truncate_partition_number;
							
							DECLARE @truncateSQL NVARCHAR(MAX) = 'TRUNCATE TABLE ' + @target_tab_name + ' WITH (PARTITIONS (' + CAST(@truncate_partition_number AS NVARCHAR(8)) + '))';
							--PRINT '@min_truncate_day: ' + CAST(@min_truncate_day AS NVARCHAR(32));
														
							SET @sql = NULL;
							/* merge partition only if it is not the first one in the table! */
							IF @truncate_partition_number > 1
								SELECT @sql = 'ALTER PARTITION FUNCTION ' + @target_partition_function + '() MERGE RANGE (CAST(''' + CONVERT(NVARCHAR, prv.value, 112) + ''' AS DATETIME2))'
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
								 WHERE p.object_id = OBJECT_ID(@target_tab_name)
								   AND ind.type IN (0,1,5)
								   AND prv.value IS NOT NULL
								   AND prv.value < CAST(DATEADD(DAY, 1, @min_truncate_day) AS DATETIME2)
								ORDER BY prv.value
								;							

							--PRINT @truncateSQL;
							IF @truncateSQL IS NOT NULL EXEC sp_executesql @truncateSQL;					
							--PRINT @sql;
							IF @sql IS NOT NULL EXEC sp_executesql @sql;

							SET @min_truncate_day = DATEADD(DAY, 1, @min_truncate_day);
						END;					
				END;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		SELECT @error_message = OBJECT_NAME(@@PROCID) + ': ' + 'XACT_STATE=' + CAST(XACT_STATE() AS VARCHAR) + ERROR_MESSAGE() + ', ' + @sql, @error_severity = ERROR_SEVERITY(), @error_state = ERROR_STATE();

		IF (XACT_STATE()) = -1  
			BEGIN  
				ROLLBACK TRANSACTION;  
			END;  
 
		IF (XACT_STATE()) = 1  
			BEGIN  
				COMMIT TRANSACTION;     
			END;  		
		INSERT INTO PartitionErrors ([Message]) VALUES (@error_message);
		RAISERROR (@error_message, @error_severity, @error_state) WITH NOWAIT;
		RETURN;
	END CATCH;	

	/* if there are other non-aggregated data return 1 in output parameter */
	IF (@date_to < @min_source_retention AND @min_source_day IS NOT NULL)
		BEGIN
			SET @next_aggregation_ready = 1;
		END;	
	/*
	PRINT 'returned @date: ' + CAST(@date AS NVARCHAR(32));
	PRINT '@next_aggregation_ready: ' + CAST(@next_aggregation_ready AS NVARCHAR(2));
	*/
END;
