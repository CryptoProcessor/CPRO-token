# Contributing to CryptoProcessor

Thank you for your interest in contributing to CryptoProcessor! We welcome contributions from the community and appreciate your effort to improve our project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Pull Request Process](#pull-request-process)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Issue Reporting](#issue-reporting)
- [Development Setup](#development-setup)
- [Contributor License Agreement](#contributor-license-agreement)

## Code of Conduct

This project adheres to a Code of Conduct. Be sure to read through our CODE_OF_CONDUCT.md document. By participating, you are expected to uphold this code. Please report unacceptable behavior to duronis01@gmail.com.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/CryptoProcessor.git`
3. Create a new branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Push to your fork and submit a pull request

## How to Contribute

### Types of Contributions

- **Bug fixes**: Fix issues reported in the issue tracker
- **Features**: Propose and implement new features
- **Documentation**: Improve or add documentation
- **Tests**: Add or improve test coverage
- **Security**: Report security vulnerabilities privately to duronis01@gmail.com

### Before You Start

- Check existing issues and PRs to avoid duplicates
- For major changes, open an issue first to discuss your proposal
- Ensure your code follows our coding standards
- Write or update tests for your changes

## Pull Request Process

All pull requests to the `main` branch require review and approval from project maintainers.

### PR Requirements

1. **Branch naming**: Use descriptive names

   - `feature/add-staking-contract`
   - `fix/token-transfer-bug`
   - `docs/update-document`

2. **Code quality**:

   - All tests must pass
   - Code must be properly formatted. For JS/TS files use the default Prettier formatting. For solidity files, use the official styling guide https://docs.soliditylang.org/en/latest/style-guide.html
   - No linting errors
   - Include descriptive comments to your classes and functions

3. **Testing**:

   - Add tests for new features
   - Ensure all existing tests pass
   - For smart contracts: include unit and integration tests

4. **Documentation**:

   - Update README.md if needed
   - Add inline code documentation
   - Update technical specs for significant changes

5. **PR Description**:

   ```markdown
   ## Description

   Brief description of changes

   ## Related Issue

   Fixes #123

   ## Type of Change

   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update

   ## Testing

   Describe testing performed

   ## Checklist

   - [ ] Code follows project style guidelines
   - [ ] Tests added/updated
   - [ ] Documentation updated
   - [ ] Commit messages follow guidelines
   ```

### Review Process

- Maintainers will review your PR. Be patient since it can take a while while the PR is approved
- Once approved, maintainers will merge your PR
- PRs may be closed if inactive for 30+ days

## Commit Message Guidelines

We follow the next commit formatting:

- Commit messages must start with one of these prefixes/scopes (uppercase): START, PROGRESS, FINISH, FIX, DEPLOYMENT, DOCS, BREAKING_CHANGE, TEST, CI,
- Message body must be descriptive: what changed, what was fixed/updated
- If the commit needs urgent attention, add '!' to the prefix like in this example: FIX!: Addressing critical issue #123 with adding new validation checks in the manager class.

### Format

```
<type>(<scope>): <subject>

<body>

```

### Examples

```
START: add staking rewards mechanism

Implement time-based staking rewards with configurable APY.
Users can now stake tokens and earn rewards proportional to stake duration.

Closes #45
```

```
FIX: resolve transfer overflow vulnerability

Fixed integer overflow in transfer function that could allow
unauthorized token minting.

BREAKING CHANGE: Updates transfer function signature
```

```
DOCS: update tokenomics section

Clarified token distribution and vesting schedules.
```

### Rules

- Use present tense ("add feature" not "added feature")
- Reference issues/PRs in footer
- Use `BREAKING_CHANGE:` for breaking changes
- Be descriptive but concise

## Issue Reporting

### Before Submitting an Issue

- Search existing issues to avoid duplicates
- Collect relevant information (versions, error messages, steps to reproduce)

### Bug Reports

Use this template:

```markdown
**Description**
Clear description of the bug

**Steps to Reproduce**

1. Step one
2. Step two
3. See error

**Expected Behavior**
What should happen

**Actual Behavior**
What actually happens

**Environment**

- OS: [e.g., Ubuntu 22.04]
- Node version: [e.g., 18.x]
- Solidity version: [e.g., 0.8.20]
- Browser: [if applicable]

**Additional Context**
Screenshots, logs, or other relevant information
```

### Feature Requests

```markdown
**Problem Statement**
Describe the problem this feature would solve

**Proposed Solution**
Your suggested implementation

**Alternatives Considered**
Other approaches you've thought about

**Additional Context**
Any other relevant information
```

### Security Issues

**DO NOT** report security vulnerabilities publicly. Email duronis01@gmail.com with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Development Setup

### Prerequisites

- Node.js >= 18.x
- npm or yarn
- Hardhat or Foundry (for smart contracts)

### Running Tests

```bash
# Run all tests
npm test

# Run specific test file
npm test test/Token.test.js

# Run with coverage
npm run coverage
```

## Contributor License Agreement

By contributing to this project, you agree that:

1. You have the right to submit the contribution
2. You grant us the rights to use your contribution under the project's license
3. Your contribution is your original work or you have permission to submit it
4. You understand that contributions may be subject to the project's patent policy (see PATENTS.md)

For significant contributions, we may ask you to sign a formal CLA or NDA.

## Questions?

- Open a discussion in GitHub Discussions
- Join our Discord/Telegram (coming soon!)
- Email us at duronis01@gmail.com

Thank you for contributing! 🚀
