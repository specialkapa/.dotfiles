- No connection to background workers intermittently on UAT
- All ECL dashboard functionality faces issues other than the Scenarios and PD Curves tabs
- We have issues with icons not working on the Logs panel
- ECL cashflows table is not working (brings 0 rows)

# RCB stress forecast

- the target back book closing balances are handed over by the RCB team
- also the front book closing balance
- also average balance for the front book
- also average term for originations/front book
- also originations amount
- we only scale stage 1 and 2
- we amortise and if we do not match the closing balance target we scale
- seems like the back book balance forecast is including pipelines

According to Ben RCB assumes that all exposures other than asset finance are expected to go beyond
the contractual term by 4 months.

Let's say I calculate the expected balances at account level correctly so they are in line with the
target forecast back book balances handed over by RCB. The starting point being the first month in
the forecast.

I can derive monthly PDs and LGDs and EAD at account level. Then I can get incremental ECLs for each
month of an accounts lifetime.

Given the vector of PDs for each account I can use the simulate PD function in Will's code to push
accounts into default, arrears or stage 2 which ultimately pushes accounts into stage 2 or 3.

At each point forecast date I can check the stage of the account and incremental ECLs (discounted)
for the next 12 months or the remaining lifetime. Discounting will have to be recalculated with the
forecast date as a reference point.

# LLM stuff

Claude code PR git integration
