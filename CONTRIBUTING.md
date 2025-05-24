# Contributing to Yume

Thank you for your interest in contributing to Yume! We welcome and greatly appreciate all contributions, whether it’s a bug fix, a new feature, documentation updates, or other improvements. Your efforts help make Yume a better project for everyone.

## Table of Contents
- [How Can I Contribute?](#how-can-i-contribute)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)
- [Pull Request Process](#pull-request-process)
- [Commit Messages](#commit-messages)
- [Styleguides](#styleguides)

## How Can I Contribute?
There are several ways to contribute:
- **Reporting Bugs:** Use GitHub issues to report any bugs.
- **Suggesting Enhancements:** Propose new features or improvements by opening an issue.
- **Improving Documentation:** Update or add documentation where necessary.
- **Submitting Pull Requests:** Fork the repository, make your changes, and submit a pull request. Please follow the guidelines below to ensure a smooth process.

## Reporting Bugs
Before reporting a bug, please:
- Verify that you are using the latest version.
- Search the [issue tracker](https://github.com/rzvxa/yume/issues) to see if the bug has already been reported.
- Provide a clear and descriptive title.
- Include detailed steps to reproduce the error, expected vs. actual behavior, and any relevant screenshots or logs.

## Suggesting Enhancements
When suggesting enhancements:
- Clearly describe the problem and why the change would be beneficial.
- Provide details of your proposed solution, including examples or mockups if applicable.
- Open an issue to discuss your idea before submitting a pull request.

## Pull Request Process
1. **Fork** the repository and create a new branch from `main`.
2. **Develop** your feature or fix following the project’s coding standards.
3. **Commit** your changes using [Conventional Commits](#commit-messages) guidelines.
4. **Test** your changes thoroughly, ensuring that all new and existing tests pass.
5. **Submit** a pull request with a detailed description of your changes.
6. **Respond** to any feedback and make necessary revisions.

## Commit Messages
We use **Conventional Commits** for our commit messages to ensure a clear, consistent history that supports automated versioning and changelog generation. Please follow the format below:

```
<type>(<scope>): <subject>
<BLANK LINE>
<body> (optional)
<BLANK LINE>
<footer> (optional, e.g. BREAKING CHANGE:)
```

Allowed types include:
- **feat:** New feature for the end user.
- **fix:** Bug fix for the end user.
- **docs:** Documentation-only changes.
- **style:** Changes that do not affect the meaning of the code (e.g., formatting).
- **refactor:** Code changes that neither fix a bug nor add a feature.
- **perf:** Code changes that improve performance.
- **test:** Adding missing tests or correcting existing tests.
- **build:** Changes that affect the build system or dependencies.
- **ci:** Changes to our continuous integration pipeline.
- **chore:** Minor changes or maintenance tasks.
- **revert:** Reverts a previous commit.

For example, a commit might look like:
```
fix(editor): lighting in the material thumbnail preview

Change the angle of light to shine on the front side of the model.
```

If your commit introduces breaking changes, include a note in the footer with `BREAKING CHANGE:` detailing the changes.

## Styleguides
- **Coding Standards:** Follow the coding style and best practices outlined in the Zig documentation.
- **Documentation:** Write clear, accessible documentation. Use Markdown formatting to ensure readability.

## Additional Resources
- [Issue Tracker](https://github.com/rzvxa/yume/issues)
- [Pull Request](https://github.com/rzvxa/yume/pulls)
- [Conventional Commits Specification](https://www.conventionalcommits.org/en/v1.0.0/)

Thank you for contributing to Yume! Your support is essential to the success and improvement of the project.