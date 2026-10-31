let
    Source = Csv.Document(File.Contents(DataRoot & "/DimPriority.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"action_priority", type text}, {"priority_order", Int64.Type}}, "en-US")
in
    Typed