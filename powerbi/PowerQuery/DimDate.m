let
    Source = Csv.Document(File.Contents(DataRoot & "/DimDate.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Headers, {{"date", type date}, {"year", Int64.Type}, {"month", Int64.Type}, {"month_name", type text}, {"weekday", type text}, {"weekday_order", Int64.Type}, {"week_number", Int64.Type}, {"quarter", Int64.Type}}, "en-US")
in
    Typed