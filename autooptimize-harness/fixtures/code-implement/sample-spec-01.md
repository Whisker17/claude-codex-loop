# Design: CLI Calculator

## Requirements
- Python CLI accepting: `calc <operation> <num1> <num2>`
- Operations: add, subtract, multiply, divide
- Handle division by zero with error message
- Validate inputs are valid numbers
- Print result to stdout
- Include unit tests covering all operations and error cases

## Architecture
- Single file `calc.py` with main() entry point
- Use argparse for CLI parsing
- Separate `calculate(op, a, b)` function for testability
- Test file `test_calc.py` using pytest
