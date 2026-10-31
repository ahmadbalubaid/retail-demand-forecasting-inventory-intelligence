let
    Source = Csv.Document(File.Contents(DataRoot & "/DimSeries.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"store_nbr", Int64.Type}, {"risk_category", type text}, {"action_priority", type text}, {"activity_status", type text}, {"volume_tier", type text}, {"family_id", Int64.Type}, {"series_key", type text}, {"series_label", type text}, {"risk_band", type text}}, "en-US")
in
    Typed