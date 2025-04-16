# Kinto Core Developer Guide

## Build & Test Commands
- Run all tests: `forge test -vvv`
- Run single test: `forge test --match-path test/unit/FileName.t.sol --match-test testFunctionName -vvv`
- Run fork tests: `FOUNDRY_PROFILE=fork forge test -vvv`
- Gas report: `forge test --gas-report`
- Coverage: `forge coverage`
- Lint: `solhint 'src/**/*.sol'`
- Static analysis: `slither .`

## Code Style Guidelines
- **Imports**: Group imports by source (OpenZeppelin, internal, etc.)
- **Naming**: Use camelCase for functions/variables, PascalCase for contracts/interfaces
- **Types**: Prefer specific types (uint256 over uint), use interface types for external calls
- **Error Handling**: Use custom errors with descriptive names instead of revert strings
- **Documentation**: Add NatSpec comments for public/external functions and state variables
  - Use `@notice` for describing what a function does (visible to end users)
  - Use `@dev` for implementation details (visible to developers)
  - Use `@param` to document each parameter
  - Use `@return` to document return values
  - Use `@inheritdoc` when implementing interface functions
  - Add only `/// @notice`
  - Document constants with `/// @notice` comments
  - Add comprehensive comments for complex structs
  - Document all custom errors with `/// @notice` comments
  - Add detailed comments for events including all parameters
- **Testing**: Follow AAA pattern (Arrange-Act-Assert), write thorough tests for all edge cases
- **Security**: Follow security best practices, add proper access control
- **Constants**: Use uppercase for constant values

## Project Structure
- `/src`: Smart contract source code
- `/test`: Test files (unit tests in `/unit`, fork tests in `/fork`)
- `/script`: Deployment scripts and migrations

## Claude Preferences
- **Commits and PRs**: Do not add Claude credits or Co-Authored-By lines to commits or PRs
- **Commit Messages**: Keep concise and descriptive, follow project conventions
- Always run 'forge fmt' after making changes to Solidity code
- Never use `--via-ir` compilation flag
