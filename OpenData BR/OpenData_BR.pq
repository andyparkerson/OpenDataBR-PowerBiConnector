/**
  * Power BI Desktop Custom Connector for OpenDataBR
  * Author: Andy Parkerson
  * Email: andyparkerson@gmail.com
  * Date: February 2018
  *
  * This connector will allow the user to connect with any of the Open Data BR endpoints. 
  * It gets the list of endpoints dynamically, and then builds the tables. Multiple
  * tables can be queried by Power BI with a single connection.
  *
  * As this uses the socrata Discovery API, it should be able to query any of the open
  * data sets using that model.
  *
  * More information can be found at {@link https://socratadiscovery.docs.apiary.io/}.
  *
  * This connector was submitted as part of the Hackathon at the 2018 Activate Conference.
  */

section OpenData_BR;

[DataSource.Kind="OpenData_BR", Publish="OpenData_BR.Publish"]

shared OpenData_BR.Contents = () =>
    let
        source = NavigationTable.Nested()
//         source = getEndPoints("transportation")
//         source = getResultSizeSet("bvrj-kevk")
//         source = getTableFromEndpoint("bvrj-kevk")
    in
        source;

// Set the attributes for Web.Contents() calls
attributes = [
    Query = [
        // We only want data from Baton Rouge
        domains = "data.brla.gov",
        // We also only want data that we can handle (datalens not supported yet)
        only = "dataset,map,filter,chart"
    ]
];

// Get the categories that the APIs are divided up into. Each category will have its own nested table
// Returns a list of category names
getDomainCategories = () =>
    let 
        source = Web.Contents("https://data.brla.gov/api/catalog/v1/categories", attributes),
        json = Json.Document(Text.FromBinary(source)),
        results = json[results],
        convertToTable = Table.FromList(results, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        columnNames = Record.FieldNames(Table.FirstValue(convertToTable)),
        ExpandedColumn1 = Table.ExpandRecordColumn(convertToTable, "Column1", columnNames),
        selectColumn = Table.Column(ExpandedColumn1, columnNames{0})
    in
        selectColumn;

getEndPoints = (category as text) =>
    let 
        categoryAttributes = [Query = Record.AddField(Record.Field(attributes, "Query"), "categories", category)],
        source = Web.Contents("https://data.brla.gov/api/catalog/v1", categoryAttributes),
        json = Json.Document(Text.FromBinary(source)),
        results = json[results],
        resultSetSize = json[resultSetSize],
        ConvertedToTable = Table.FromList(results, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        ExpandedColumn1 = Table.ExpandRecordColumn(ConvertedToTable, "Column1", {"resource", "classification", "metadata", "permalink", "link", "owner"}, {"Column1.resource", "Column1.classification", "Column1.metadata", "Column1.permalink", "Column1.link", "Column1.owner"}),
        ExpandedColumn1.classification  = Table.ExpandRecordColumn(ExpandedColumn1, "Column1.classification", {"domain_category"}, {"Column1.classification.domain_category"}),
        ExpandedColumn1.resource  = Table.ExpandRecordColumn(ExpandedColumn1.classification, "Column1.resource", {"name", "id", "description", "type"}, {"Column1.resource.name", "Column1.resource.id", "Column1.resource.description", "Column1.resource.type"}),
        RemovedColumns = Table.RemoveColumns(ExpandedColumn1.resource,{"Column1.metadata", "Column1.owner"}),
        RenamedColumns = Table.RenameColumns(RemovedColumns,{{"Column1.resource.name", "Name"}}),
        ChangedType = Table.TransformColumnTypes(RenamedColumns,{{"Name", type text}, {"Column1.resource.id", type text}}),
        RenamedColumns1 = Table.RenameColumns(ChangedType,{{"Column1.resource.id", "Key"}}),
        ChangedType1 = Table.TransformColumnTypes(RenamedColumns1,{{"Column1.resource.description", type text}}),
        RenamedColumns2 = Table.RenameColumns(ChangedType1,{{"Column1.resource.description", "Description"}, {"Column1.resource.type", "Type"}, {"Column1.classification.domain_category", "DomainCategory"}, {"Column1.permalink", "PermalinkUrl"}, {"Column1.link", "Url"}})
    in
        RenamedColumns2;

getTableFromEndpoint = (endPoint as text) => 
    let
        limit = 10,
        resultSizeSet = getResultSizeSet(endPoint),
        ResultList = List.Generate(()=>0, each _ < resultSizeSet, each _ + limit),
        tableList = List.Transform(ResultList, each getTableFromEndpointPaging(endPoint, limit, _)),
        tableCombine = Table.Combine(tableList)
    in
        tableCombine;

getTableFromEndpointPaging = (endPoint as text, limit as number, offset as number) => 
    let 
        source = Web.Contents("https://data.brla.gov/resource/" & endPoint & ".json?$limit=" & Number.ToText(limit) & "&$offset=" & Number.ToText(offset)),
        json = Json.Document(Text.FromBinary(source)),
        ConvertedToTable = Table.FromList(json, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        first = Table.FirstValue(ConvertedToTable),
        fieldNames = Record.FieldNames(first),
        expand = Table.ExpandRecordColumn(ConvertedToTable, "Column1", fieldNames)
    in
        expand;

getResultSizeSet = (endPoint as text) =>
    let
        source = Web.Contents("https://data.brla.gov/resource/" & endPoint & ".json?$select=count(*)"),
        json = Json.Document(Text.FromBinary(source)),
        countRecord = List.First(json),
        count = Number.FromText(countRecord[count])
    in
        count;

getEndPointNavTable = (category as text) =>
    let
        endpoints = getEndPoints(category),
        removeColumns = Table.SelectColumns(endpoints, {"Key", "Type", "Name"}),
        changeTypes = Table.TransformColumnTypes(removeColumns, {{"Key", type text}, {"Type", type text}, {"Name", type text}}),
        getTable = Table.AddColumn(changeTypes, "Data", each getTableFromEndpoint(_[Key]), type table),
        addItemKind = Table.AddColumn(getTable, "ItemKind", each "Table"),
        addItemName = Table.AddColumn(addItemKind, "ItemName", each "Table"),
        addLeaf = Table.AddColumn(addItemName, "IsLeaf", each true),
        removeColumns2 = Table.RemoveColumns(addLeaf, {"Type"}),
        reorderColumns = Table.ReorderColumns(removeColumns2,{"Name", "Key", "Data","ItemKind", "ItemName", "IsLeaf"})

    in
        reorderColumns;

getCategoryNavTable = () => 
    let
        categoryList = getDomainCategories(),
        categoryTable = Table.FromList(categoryList),
        renameColumn = Table.RenameColumns(categoryTable, {{"Column1", "Name"}}),
        getTable = Table.AddColumn(renameColumn, "Data", each CreateNavTable(_[Name]), type table),
        addKey = Table.AddColumn(getTable, "Key", each Text.Range([Name], 0, 4)),
        addItemKind = Table.AddColumn(addKey, "ItemKind", each "Table"),
        addItemName = Table.AddColumn(addItemKind, "ItemName", each "Table"),
        addLeaf = Table.AddColumn(addItemName, "IsLeaf", each false),
        reorderColumns = Table.ReorderColumns(addLeaf,{"Name", "Key", "Data","ItemKind", "ItemName", "IsLeaf"})
    in
        reorderColumns;

shared NavigationTable.Nested = () as table =>
    let
        objects = getCategoryNavTable(),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

CreateNavTable = (category as text) =>
    let
        objects = getEndPointNavTable(category),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;


// Data Source Kind description
OpenData_BR = [
    Authentication = [
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
OpenData_BR.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/andyparkerson/OpenDataBR-PowerBiConnector",
    SourceImage = OpenData_BR.Icons,
    SourceTypeImage = OpenData_BR.Icons
];

OpenData_BR.Icons = [
    Icon16 = { Extension.Contents("OpenData_BR16.png"), Extension.Contents("OpenData_BR20.png"), Extension.Contents("OpenData_BR24.png"), Extension.Contents("OpenData_BR32.png") },
    Icon32 = { Extension.Contents("OpenData_BR32.png"), Extension.Contents("OpenData_BR40.png"), Extension.Contents("OpenData_BR48.png"), Extension.Contents("OpenData_BR64.png") }
];
