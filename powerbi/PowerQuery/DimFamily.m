let
    Source = Csv.Document(File.Contents(DataRoot & "/DimFamily.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"family_id", Int64.Type}, {"family", type text}}, "en-US")
in
    Typed