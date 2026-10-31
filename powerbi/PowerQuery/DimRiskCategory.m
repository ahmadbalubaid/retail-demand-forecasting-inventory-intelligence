let
    Source = Csv.Document(File.Contents(DataRoot & "/DimRiskCategory.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"risk_category", type text}, {"severity", Int64.Type}, {"color", type text}}, "en-US")
in
    Typed