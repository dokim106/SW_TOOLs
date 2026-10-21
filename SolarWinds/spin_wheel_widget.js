var data = [
  { id: "root", parent: "", name: "Nodes" },
  { id: "vendor:Cisco", parent: "root", name: "Cisco" },
  { id: "vendor:Meraki", parent: "root", name: "Meraki" },
  { id: "vendor:Unknown", parent: "root", name: "Unknown" },
  { id: "vendor:VMware", parent: "root", name: "VMware" },
  { id: "vendor:Windows", parent: "root", name: "Windows" },

  {
    id: "vendor:Cisco:2",
    parent: "vendor:Cisco",
    name: "Down",
    color: "#dc2626",
  },
  {
    id: "vendor:Meraki:12",
    parent: "vendor:Meraki",
    name: "unreach",
    color: "#fb923c",
  },
  {
    id: "vendor:Meraki:2",
    parent: "vendor:Meraki",
    name: "Down",
    color: "#dc2626",
  },
  {
    id: "vendor:Unknown:11",
    parent: "vendor:Unknown",
    name: "Ext",
    color: "#2563eb",
  },
  {
    id: "vendor:Unknown:2",
    parent: "vendor:Unknown",
    name: "Down",
    color: "#dc2626",
  },
  {
    id: "vendor:VMware:2",
    parent: "vendor:VMware",
    name: "Down",
    color: "#dc2626",
  },
  {
    id: "vendor:Windows:2",
    parent: "vendor:Windows",
    name: "Down",
    color: "#dc2626",
  },
  {
    id: "vendor:Windows:3",
    parent: "vendor:Windows",
    name: "Warn",
    color: "#f59e0b",
  },

  {
    id: "leaf:Cisco:2:1",
    parent: "vendor:Cisco:2",
    name: "8.8.8.1-amit",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:88",
  },
  {
    id: "leaf:Meraki:12:2",
    parent: "vendor:Meraki:12",
    name: "Printer",
    value: 1,
    color: "#fb923c",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:7",
  },
  {
    id: "leaf:Meraki:2:3",
    parent: "vendor:Meraki:2",
    name: "Lobby",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:6",
  },
  {
    id: "leaf:Unknown:11:4",
    parent: "vendor:Unknown:11",
    name: "cisc.com",
    value: 1,
    color: "#2563eb",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:89",
  },
  {
    id: "leaf:Unknown:11:5",
    parent: "vendor:Unknown:11",
    name: "solarwinds.com",
    value: 1,
    color: "#2563eb",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:90",
  },
  {
    id: "leaf:Unknown:11:6",
    parent: "vendor:Unknown:11",
    name: "support",
    value: 1,
    color: "#2563eb",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:86",
  },
  {
    id: "leaf:Unknown:11:7",
    parent: "vendor:Unknown:11",
    name: "www.bbc.co.uk",
    value: 1,
    color: "#2563eb",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:105",
  },
  {
    id: "leaf:Unknown:2:8",
    parent: "vendor:Unknown:2",
    name: "robby",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:100",
  },
  {
    id: "leaf:Unknown:2:9",
    parent: "vendor:Unknown:2",
    name: "XM2600",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:101",
  },
  {
    id: "leaf:VMware:2:10",
    parent: "vendor:VMware:2",
    name: "ESX1",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:103",
  },
  {
    id: "leaf:VMware:2:11",
    parent: "vendor:VMware:2",
    name: "ESX2",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:99",
  },
  {
    id: "leaf:Windows:2:12",
    parent: "vendor:Windows:2",
    name: "SQL1",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:33",
  },
  {
    id: "leaf:Windows:2:13",
    parent: "vendor:Windows:2",
    name: "HYPERV06",
    value: 1,
    color: "#dc2626",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:53",
  },
  {
    id: "leaf:Windows:3:14",
    parent: "vendor:Windows:3",
    name: "SWOSH",
    value: 1,
    color: "#f59e0b",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:1",
  },
  {
    id: "leaf:Windows:3:15",
    parent: "vendor:Windows:3",
    name: "DPA1",
    value: 1,
    color: "#f59e0b",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:10",
  },
  {
    id: "leaf:Windows:3:16",
    parent: "vendor:Windows:3",
    name: "DC02",
    value: 1,
    color: "#f59e0b",
    url: "/Orion/NetPerfMon/NodeDetails.aspx?NetObject=N:16",
  },
];

var chartsunBurst = Highcharts.chart("sunBurst", {
  chart: { borderWidth: 0, plotBorderWidth: 0 },
  title: { text: "" },
  exporting: { enabled: false },
  credits: { enabled: false },
  plotOptions: { sunburst: { borderWidth: 0 } },
  title: { text: "Nodes by Vendor & Status" },
  series: [
    {
      type: "sunburst",
      allowDrillToNode: true,
      levelIsConstant: false,
      data: data,
      dataLabels: {
        rotationMode: "circular",
        style: { textOutline: "none" },
        filter: { property: "outerArcLength", operator: ">", value: 20 }, // reduce clutter
      },
      levels: [
        {
          level: 1,
          levelIsConstant: false,
          dataLabels: { style: { fontWeight: "bold" } },
        },
        {
          level: 2,
          dataLabels: {
            formatter: function () {
              console.log("this.node.level 2", this.point.node.level);
              if (this.point.node.level === 4) {
                return `${this.point.name}`;
              } else {
                const count =
                  typeof this.point.value === "number" ? this.point.value : 0;
                return `${this.point.name}<br>(${count})`;
              }
            },
          },
          colorByPoint: true,
        },
        {
          level: 3,
          dataLabels: {
            formatter: function () {
              //console.log('this.node.level',node.level);
              if (this.point.node.level === 4) {
                return `${this.point.name}`;
              } else {
                const count =
                  typeof this.point.value === "number" ? this.point.value : 0;
                return `${this.point.name} (${count})`;
              }
            },
          },
        },
        {
          level: 4,
          hidden: true,
          dataLabels: { enabled: false },
          levelSize: { value: 0 },
          colorByPoint: true,
        },
      ],
      point: {
        events: {
          click: function () {
            if (this.url) {
              window.open(this.url, "_blank");
            } else if (
              this.drilldown ||
              (this.node && this.node.children && this.node.children.length)
            ) {
            }
          },
        },
      },
    },
  ],
  tooltip: {
    pointFormat:
      "<b>{point.name}</b><br/>{#if point.value}Count: {point.value}{/if}",
  },
});
