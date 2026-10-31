let
    Source = Csv.Document(File.Contents(DataRoot & "/DimStore.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"store_nbr", Int64.Type}, {"store_label", type text}, {"city", type text}, {"state", type text}, {"store_type", type text}, {"cluster", Int64.Type}}, "en-US")
in
    Typed