# Bank Statement → YNAB CSV Converters

Two Elixir scripts that transform bank statement CSVs into the standard [YNAB](https://www.ynab.com/) import format (`Date, Payee, Memo, Outflow, Inflow`).

## Prerequisites

- **Elixir 1.12+** — required by `csv-capital-one-to-ynab.exs` (uses `Mix.install/1`).
  `csv-aba-to-ynab.exs` uses only stdlib but runs on the same version.

## Scripts

### `csv-aba-to-ynab.exs` — ABA Cambodia

Converts ABA Mobile / Internet Banking statement CSVs to YNAB format.

#### Usage

```
elixir csv-aba-to-ynab.exs <input_csv_path> <output_csv_path>
elixir csv-aba-to-ynab.exs -h | --help
```

Both arguments are **required**.

#### Example

```shell
elixir csv-aba-to-ynab.exs statement.csv ynab_output.csv
```

#### Supported Transaction Descriptions

The script parses ABA's `Transaction Details` column and extracts a clean payee:

| ABA Description Pattern       | YNAB Payee                           |
|-------------------------------|--------------------------------------|
| `PURCHASE AT <merchant> ...`  | `<merchant>`                         |
| `FUNDS TRANSFERRED TO <name>` | `<name>`                             |
| `CASH DEPOSIT FROM <name>`    | `Deposit: <name>`                    |
| `ATM CASH WITHDRAWAL`         | `ATM Withdrawal`                     |
| `REFUND BY <merchant> ...`    | `<merchant> Refund`                  |
| *(anything else)*             | First 30 characters of the raw memo  |

#### Input Format

ABA CSV lines matching the pattern:

```
"Mon DD, YYYY","Transaction Details ...",<money_in>,<ccy>,<money_out>,<ccy>,<balance>,<ccy>
```

The header rows (`ACCOUNT ACTIVITY`, `Date,Transaction Details`) and blank lines are automatically skipped.

- Dates: `"Dec 24, 2024"` → `2024-12-24`
- Amounts: commas removed (ABA uses `,` as thousand separator)

#### Dependencies

None — pure Elixir stdlib (`File`, `Stream`, `Regex`, `OptionParser`).

---

### `csv-capital-one-to-ynab.exs` — Capital One (USA)

Converts Capital One **Credit Card** and **Bank Account / Savings** statement CSVs to YNAB format.

#### Usage

```
elixir csv-capital-one-to-ynab.exs <input_csv_path> [output_csv_path]
```

- If `output_csv_path` is omitted, the output is written to `<input_stem>_ynab.csv` (same directory as the input).

#### Examples

```shell
# Output auto-named: transactions_ynab.csv
elixir csv-capital-one-to-ynab.exs transactions.csv

# Explicit output path
elixir csv-capital-one-to-ynab.exs statement.csv ynab_ready.csv
```

#### Auto-Detected Layouts

**Credit Card** (columns: `Transaction Date`, `Posted Date`, `Card No.`, `Description`, `Category`, `Debit`, `Credit`)

| YNAB Column | Source Column        |
|-------------|----------------------|
| Date        | `Transaction Date`   |
| Payee       | `Description`        |
| Memo        | `Category`           |
| Outflow     | `Debit`              |
| Inflow      | `Credit`             |

**Bank Account / Savings** (columns: `Account Number`, `Transaction Description`, `Transaction Date`, `Transaction Type`, `Transaction Amount`, `Balance`)

| YNAB Column | Source Column               |
|-------------|-----------------------------|
| Date        | `Transaction Date`          |
| Payee       | `Transaction Description`   |
| Memo        | `Transaction Type`          |
| Outflow     | Negative amount, or debit/withdrawal/payment |
| Inflow      | Positive amount (non-debit) |

#### Transformations

- **Dates**: `MM/DD/YY` or `MM/DD/YYYY` → `YYYY-MM-DD` (2-digit years assume 20xx).
- **Amounts**: `$` signs and commas stripped, then parsed as numeric.
- **Bank Account Outflow/Inflow**: Negative amounts always become Outflow. Positive amounts check `Transaction Type` — `debit`, `withdrawal`, or `payment` → Outflow; everything else → Inflow.

#### Dependencies

- [nimble_csv](https://hex.pm/packages/nimble_csv) `~> 1.2` — automatically installed at runtime via `Mix.install/1`.

---

## Output Format

Both scripts produce CSVs with these columns:

```
Date,Payee,Memo,Outflow,Inflow
2024-12-24,Some Merchant,purchase,45.99,
2024-12-25,Deposit: Me,,,500.00
```

- **Date**: `YYYY-MM-DD` (ISO 8601)
- **Payee**: Cleaned merchant or counterparty name
- **Memo**: Raw transaction description or category
- **Outflow**: Money leaving the account (positive number, empty if inflow)
- **Inflow**: Money entering the account (positive number, empty if outflow)

This layout is ready for direct import into YNAB via **File > Import > CSV**.

---

## Supported Banks

| Bank                      | Script                     | Layout Auto-Detect     |
|---------------------------|----------------------------|------------------------|
| ABA (Cambodia)            | `csv-aba-to-ynab.exs`      | No (single format)     |
| Capital One (USA) — Credit Card  | `csv-capital-one-to-ynab.exs` | Yes                |
| Capital One (USA) — Bank Account | `csv-capital-one-to-ynab.exs` | Yes                |

---

## Notes

- Both scripts are self-contained and stateless — run them as many times as you like.
- `csv-aba-to-ynab.exs` reads the entire file into memory (uses `Enum.to_list/1`); fine for typical personal-banking statement sizes.
- `csv-capital-one-to-ynab.exs` streams the file line-by-line, making it suitable for larger exports.
- Neither script modifies the input file.
- For YNAB import, CSV files must use UTF-8 encoding (both scripts produce UTF-8 by default).
