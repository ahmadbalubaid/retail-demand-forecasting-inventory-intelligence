let
    Source = Csv.Document(File.Contents(DataRoot & "/FactForecast.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"date", type date}, {"series_key", type text}, {"predicted_sales", type number}, {"onpromotion", Int64.Type}, {"forecast_horizon", Int64.Type}}, "en-US")
in
    Typed