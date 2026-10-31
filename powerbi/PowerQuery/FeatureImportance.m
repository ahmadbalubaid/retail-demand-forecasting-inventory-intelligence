let
    Source = Csv.Document(File.Contents(DataRoot & "/FeatureImportance.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"feature", type text}, {"gain_share", type number}}, "en-US")
in
    Typed