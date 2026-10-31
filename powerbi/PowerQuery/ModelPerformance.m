let
    Source = Csv.Document(File.Contents(DataRoot & "/ModelPerformance.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"model", type text}, {"mean_rmsle", type number}, {"selected", Int64.Type}, {"provenance", type text}}, "en-US")
in
    Typed