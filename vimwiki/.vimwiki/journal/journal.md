# Journal

# 2025-11-14

- [x] Fix error in ECL dashboard cashflows
- [x] Investigate Recognise bank Bridging Commercial low ECL
- [x] Reporting including existence checks, viability checks and building should run on the main
      thread
  - [x] test for Recognise bank
  - [x] test for Bank Dhofar

# 2025-11-17

- [x] Debug Recognise bank web sockets issue on UAT
- [x] Gatehouse Bank
  - [x] Source origination balance from the other table
  - [x] Reach out to Garry for Will's VPN connection

# 2025-11-18

- [x] add additional columns to Gatehouse Bank ECL outputs

# 2025-11-19

- [x] Test non in scope for Gatehouse Bank with additional columns and affordability calculation
      switched on
- [x] debug issues in Recognise Bank deployment
- [x] ifrs9 navigator db efficiency PR review

# 2025-11-20

- [x] debug issues in Recognise Back dashboards
- [x] debug websocket no connction

# 2025-11-25

- [x] understand and refactor Will's
- [x] identify issues in Will's code
- [x] identify parts of the code that will be replaced by logic in the ECL engine

# 2025-11-26

- [x] talk with Olga regarding expected new products
- [x] figure out mapping between old and new products in Will's code
- [x] implement 50% repayment at end of term and 50% 4 months later for interest only and bridging
      products. Finally update analysis comparing the back book balance forecast comparison analysis

# 2025-11-28

- [x] agree of way foreword for the back book balance forecast
- [x] start updating the standard ecl calculation to accommodate for stress forecast

# 2025-12-01

- [x] implement new PD model components for Gatehouse Bank
- [x] implement new LGD model components for Gatehouse Bank
- [x] expose FSD and PPD parameters to the `prefect` UI
- [x] update Gatehouse Bank testing suite and run
- [x] adding necessary `alembic` revisions for new ECL flow run parameters
- [x] replicate all outstanding pull requests from bitbucket to github.
- [x] respond to audit queries on the Gatehouse Bank recalibration.

# 2025-12-02

- [x] resolve all conflicts with main since the massive changes introduced in the ECL navigator for
      database and caching optimisation.
- [x] finalise the LGD and PD model component pull requests on the github side and merge them.
- [x] fix minor issues that slipped through pull request reviews in the Gatehouse Bank ECL engine.

# 2025-12-03

- [x] make sure that economic scenarios in ECL engine are overridden with those in the stress
      forecast config if an only if `is_stress_forecast = True`.
- [x] debug $R^2$ metric calculation in the `tnp_statistics_library`.

# 2025-12-04

- [x] deploy recalibrated models + additional requested changes for Gatehouse Bank.

# 2025-12-09

- [x] fix bugs in Gatehouse Bank deployment.

# 2025-12-11

- [x] port stress forecast prototype into ECL navigator for demo with Recognise Bank.
- [x] lead ECL navigator training session for Recognise Bank users.

# 2025-12-15

- [x] optimised Monte Carlo simulation for stress forecast in ECL navigator.
- [x] optimised the attrition rate application for the stress forecast in ECL navigator.
- [x] optimised the stick rate application for the stress forecast in ECL navigator.
- [x] optimised the generation on synthetic originations for the stress forecast in ECL navigator.

# 2025-12-16

- [x] profiled the performance of the stress forecast implementation in ECL navigator.
- [x] refactored some parts to utilise the lazy `polars` API instead of eager evaluation.
- [x] optimised the stratified sampling for the stick rate application using hashing and ranking
      along with the lazy `polars` API.

# 2025-12-17

- [x] stress forecast optimisations continued.

# 2025-12-18

- [x] stress forecast optimisations continued.

# 2025-12-19

- [x] setting WSL environment from scratch.

# 2025-12-22

- [x] Recognise Bank stress forecast: ensure that defaults remain on book until write off even if
      going past their maturity date.
- [x] Recognise Bank stress forecast: ensure sticky accounts are not allowed to default of attrite
      across their whole lifetime and not just for one month.
- [x] Recognise Bank stress forecast: ensure that the default balance is carried forward + monthly
      missed interest for defaults.

# 2025-12-23

- [x] Recognise Bank stress forecast
  - [x] Store balance summaries by chunk, batch, iteration, date, backbook/frontbook and forecast
        segment name to `redis`.
  - [x] Once all batched, chunks and iterations are done, apportion the balance forecast target
        across the different dimensions and derive appropriate scaling factors to adjust facility
        level balances such that the actual forecast matches the target forecast.

# 2026-01-05

- [x] Recognise Bank stress forecast
  - [x] debug balance scaling
  - [ ] why is the account synthetic-bcd202511306-01 rolling from stage 3 to stage 1. Default should
        be an absorbing state.

# 2026-01-09 - 2026-01-16

- tying loose ends on Recognise Bank stress forecast implementation
- brief demo of the stress forecast solution to Recognise Bank team
- training session on ECL navigator stress forecast to Recognise Bank team

# 2015-01-19

- [x] fixing bug in complex waterfall chart in ECL navigator
- [x] meeting to prep for sale demo for ECL navigator

# 2026-01-20

- [x] fix little bugs in ECL Navigator
- [x] prepare for ECL Navigator demo with potential client

# 2026-01-21

- [ ] Todo item
