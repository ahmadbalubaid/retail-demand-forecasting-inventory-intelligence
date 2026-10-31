let
    Source = Csv.Document(File.Contents(DataRoot & "/ValidationFolds.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"fold", type text}, {"origin", type date}, {"ensemble_rmsle", type number}}, "en-US")
in
    Typed