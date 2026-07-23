#!/usr/bin/env elixir

defmodule YnabConverter do
  @months %{
    "Jan" => "01",
    "Feb" => "02",
    "Mar" => "03",
    "Apr" => "04",
    "May" => "05",
    "Jun" => "06",
    "Jul" => "07",
    "Aug" => "08",
    "Sep" => "09",
    "Oct" => "10",
    "Nov" => "11",
    "Dec" => "12"
  }

  def main(args) do
    {opts, extra, _invalid} =
      OptionParser.parse(args, aliases: [h: :help], switches: [help: :boolean])

    cond do
      opts[:help] ->
        show_help()

      length(extra) == 2 ->
        [input_path, output_path] = extra
        run_conversion(input_path, output_path)

      true ->
        IO.puts(:stderr, "Error: Invalid or missing arguments.\n")
        show_help()
        System.halt(1)
    end
  end

  defp show_help do
    IO.puts("""
    YNAB Converter - Convert bank statement CSV to YNAB compatible format.

    Usage:
      elixir convert_to_ynab.exs <input_csv_path> <output_csv_path>
      elixir convert_to_ynab.exs -h | --help

    Arguments:
      input_csv_path    Path to the source bank statement CSV file.
      output_csv_path   Path where the converted YNAB CSV file will be saved.
    """)
  end

  defp run_conversion(input_path, output_path) do
    IO.puts("Step 1 of 4: Verifying input file...")

    if not File.exists?(input_path) do
      IO.puts(:stderr, "Error: Input file does not exist at '#{input_path}'")
      System.halt(1)
    end

    IO.puts("Step 2 of 4: Reading and parsing CSV lines...")
    headers = ["Date", "Payee", "Memo", "Outflow", "Inflow"]

    rows =
      input_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(
        &(&1 == "" or String.starts_with?(&1, ["ACCOUNT ACTIVITY", "Date,Transaction Details"]))
      )
      |> Stream.map(&parse_line/1)
      |> Stream.reject(&is_nil/1)
      |> Enum.to_list()

    total_rows = length(rows)
    IO.puts("Step 3 of 4: Transformed #{total_rows} transactions successfully.")

    IO.puts("Step 4 of 4: Writing output to '#{output_path}'...")

    csv_content =
      [headers | rows]
      |> Enum.map(&serialize_row/1)
      |> Enum.join("\n")

    case File.write(output_path, csv_content) do
      :ok ->
        IO.puts("\nSuccess: Converted #{total_rows} rows to YNAB format.")

      {:error, reason} ->
        IO.puts(:stderr, "Error: Could not write file. Reason: #{reason}")
        System.halt(1)
    end
  end

  defp parse_line(line) do
    case Regex.run(~r/^"([^"]+)",(.*)$/, line) do
      [_, date_str, rest] ->
        tail_regex = ~r/,([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$/

        case Regex.run(tail_regex, rest) do
          [tail, money_in, _ccy1, money_out, _ccy2, _balance, _ccy3] ->
            details_raw = String.replace(rest, tail, "")

            details =
              details_raw |> String.replace_prefix("\"", "") |> String.replace_suffix("\"", "")

            date_formatted = parse_date(date_str)
            payee = extract_payee(details)
            memo = details |> String.trim() |> String.replace("\\/", "/")
            outflow = money_out |> String.replace(",", "") |> String.trim()
            inflow = money_in |> String.replace(",", "") |> String.trim()

            [date_formatted, payee, memo, outflow, inflow]

          nil ->
            nil
        end

      nil ->
        nil
    end
  end

  defp parse_date(date_str) do
    case Regex.run(~r/([A-Za-z]{3})\s+(\d{2}),\s+(\d{4})/, date_str) do
      [_, month, day, year] -> "#{year}-#{@months[month]}-#{day}"
      nil -> date_str
    end
  end

  defp extract_payee(details) do
    details_clean = details |> String.trim() |> String.replace("\\/", "/")
    details_upper = String.upcase(details_clean)

    cond do
      String.contains?(details_upper, "PURCHASE AT") ->
        case Regex.run(~r/PURCHASE AT\s+([^,]+?)(?:\s+ON\s+|\s+ORIGINAL\s+|$)/i, details_clean) do
          [_, payee] -> String.trim(payee)
          nil -> details_clean
        end

      String.contains?(details_upper, "FUNDS TRANSFERRED TO") ->
        case Regex.run(~r/FUNDS TRANSFERRED TO\s+([^,0-9]+)/i, details_clean) do
          [_, payee] -> String.trim(payee)
          nil -> details_clean
        end

      String.contains?(details_upper, "CASH DEPOSIT FROM") ->
        case Regex.run(~r/CASH DEPOSIT FROM\s+([^,0-9]+)/i, details_clean) do
          [_, payee] -> "Deposit: " <> String.trim(payee)
          nil -> details_clean
        end

      String.contains?(details_upper, "ATM CASH WITHDRAWAL") ->
        "ATM Withdrawal"

      String.contains?(details_upper, "REFUND BY") ->
        case Regex.run(~r/REFUND BY\s+([^,]+?)(?:\s+ORIGINAL\s+|$)/i, details_clean) do
          [_, payee] -> String.trim(payee) <> " Refund"
          nil -> details_clean
        end

      true ->
        details_clean |> String.slice(0, 30) |> String.trim()
    end
  end

  defp serialize_row(row) do
    row
    |> Enum.map(fn val ->
      escaped = String.replace(val, "\"", "\"\"")

      if String.contains?(val, [",", "\"", "\n"]) do
        "\"" <> escaped <> "\""
      else
        escaped
      end
    end)
    |> Enum.join(",")
  end
end

YnabConverter.main(System.argv())
