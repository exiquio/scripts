#!/usr/bin/env elixir

Mix.install([
  {:nimble_csv, "~> 1.2"}
])

# Define standard RFC4180 CSV parser
NimbleCSV.define(MyParser, separator: ",", escape: "\"")

defmodule CapitalOneToYnab do
  @doc """
  Converts Capital One CSV formats to YNAB CSV format.
  Supports:
  1. Credit Card (Transaction Date, Posted Date, Card No., Description, Category, Debit, Credit)
  2. Bank Account / Savings (Account Number, Transaction Description, Transaction Date, Transaction Type, Transaction Amount, Balance)
  """
  def convert(input_path, output_path) do
    input_path
    |> File.stream!()
    |> MyParser.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      headers, nil ->
        format_info = detect_format(headers)
        IO.puts("Detected layout: #{elem(format_info, 0) |> to_string() |> String.upcase()}")
        {[], format_info}

      row, format_info ->
        {[process_row(row, format_info)], format_info}
    end)
    |> prepend_headers()
    |> MyParser.dump_to_stream()
    |> Stream.into(File.stream!(output_path))
    |> Stream.run()

    IO.puts("Successfully converted: #{input_path} -> #{output_path}")
  end

  defp detect_format(headers) do
    headers = Enum.map(headers, &String.trim/1)

    cond do
      Enum.any?(headers, &(&1 == "Debit")) and Enum.any?(headers, &(&1 == "Credit")) ->
        {:credit_card,
         %{
           date: Enum.find_index(headers, &(&1 == "Transaction Date")),
           payee: Enum.find_index(headers, &(&1 == "Description")),
           memo: Enum.find_index(headers, &(&1 == "Category")),
           debit: Enum.find_index(headers, &(&1 == "Debit")),
           credit: Enum.find_index(headers, &(&1 == "Credit"))
         }}

      Enum.any?(headers, &(&1 == "Transaction Amount")) ->
        {:bank_account,
         %{
           date: Enum.find_index(headers, &(&1 == "Transaction Date")),
           payee: Enum.find_index(headers, &(&1 == "Transaction Description")),
           type: Enum.find_index(headers, &(&1 == "Transaction Type")),
           amount: Enum.find_index(headers, &(&1 == "Transaction Amount"))
         }}

      true ->
        raise "Unknown CSV header format. Expected Credit Card or Bank Account headers. Found: #{inspect(headers)}"
    end
  end

  defp process_row(row, {:credit_card, indices}) do
    date = Enum.at(row, indices.date) |> normalize_date()
    payee = Enum.at(row, indices.payee)
    memo = Enum.at(row, indices.memo)
    outflow = Enum.at(row, indices.debit) |> clean_amount()
    inflow = Enum.at(row, indices.credit) |> clean_amount()

    [date, payee, memo, outflow, inflow]
  end

  defp process_row(row, {:bank_account, indices}) do
    date = Enum.at(row, indices.date) |> normalize_date()
    payee = Enum.at(row, indices.payee)
    type = Enum.at(row, indices.type) |> String.trim() |> String.downcase()
    amount_str = Enum.at(row, indices.amount) |> clean_amount()

    {outflow, inflow} =
      case Float.parse(amount_str) do
        {val, _} when val < 0 ->
          {to_string(abs(val)), ""}

        {val, _} ->
          if type in ["debit", "withdrawal", "payment"] do
            {to_string(val), ""}
          else
            {"", to_string(val)}
          end

        _ ->
          {"", ""}
      end

    [date, payee, String.capitalize(type), outflow, inflow]
  end

  # Normalizes "MM/DD/YY" or "MM/DD/YYYY" to "YYYY-MM-DD"
  defp normalize_date(date) do
    date = String.trim(date)

    if String.contains?(date, "/") do
      case String.split(date, "/") do
        [m, d, y] ->
          y = normalize_year(y)
          m = String.pad_leading(m, 2, "0")
          d = String.pad_leading(d, 2, "0")
          "#{y}-#{m}-#{d}"

        _ ->
          date
      end
    else
      date
    end
  end

  defp normalize_year(y) do
    case String.length(y) do
      2 -> "20" <> y
      4 -> y
      _ -> y
    end
  end

  defp clean_amount(nil), do: ""
  defp clean_amount(""), do: ""

  defp clean_amount(val) do
    val
    |> String.trim()
    |> String.replace("$", "")
    |> String.replace(",", "")
  end

  defp prepend_headers(stream) do
    headers = [["Date", "Payee", "Memo", "Outflow", "Inflow"]]
    Stream.concat(headers, stream)
  end
end

case System.argv() do
  [input_file] ->
    output_file = Path.rootname(input_file) <> "_ynab.csv"
    CapitalOneToYnab.convert(input_file, output_file)

  [input_file, output_file] ->
    CapitalOneToYnab.convert(input_file, output_file)

  _ ->
    IO.puts("Usage: elixir capital_one_to_ynab.exs <input_file.csv> [output_file.csv]")
    System.halt(1)
end
