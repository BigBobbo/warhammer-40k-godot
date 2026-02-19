# GitHub Actions CI/CD Workflows

This directory contains GitHub Actions workflows for automated testing, building, and maintenance of the Warhammer 40k Godot game project.

## 🚀 Workflows Overview

### 1. `test-suite.yml` - Main Testing Pipeline

**Triggers:**
- Push to any branch (tests run on every commit)
- Pull requests to `main` or `develop`
- Manual dispatch

**Jobs:**
- **Test:** Runs comprehensive GUT test suite across all test categories
- **Build Verification:** Ensures project builds successfully
- **Performance Tests:** Validates performance benchmarks
- **Code Quality:** Checks GDScript syntax and project structure
- **Security Scan:** Scans for potential security issues
- **Documentation Check:** Validates documentation completeness

**Test Categories:**
- Unit Tests (`tests/unit/`)
- Integration Tests (`tests/integration/`)
- Network Tests (`tests/network/`)

### 2. `release-build.yml` - Release Pipeline

**Triggers:**
- GitHub releases
- Manual dispatch with version input

**Jobs:**
- **Pre-Release Testing:** Full test suite validation before building
- **Multi-Platform Builds:** Builds for Linux, Windows, and macOS
- **Release Asset Creation:** Packages and uploads build artifacts
- **Post-Release Validation:** Confirms successful release

**Platforms:**
- Linux (x86_64)
- Windows (x64)
- macOS (Universal)

### 3. `maintenance.yml` - Maintenance & Monitoring

**Triggers:**
- Weekly schedule (Sundays at 2 AM UTC)
- Manual dispatch

**Jobs:**
- **Godot Updates:** Checks for new Godot Engine releases
- **GUT Updates:** Monitors GUT testing framework updates
- **Test Health Check:** Weekly test suite health validation
- **Artifact Cleanup:** Removes old build artifacts (30+ days)
- **Performance Baseline:** Tracks test performance over time
- **Security Audit:** Regular security scanning

## 🧪 Test Execution

### Local Testing
```bash
# Run all tests
cd 40k
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests

# Run specific test category
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests/unit

# Run with XML output for CI
godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gjunit_xml_file=results.xml
```

### CI Test Execution
Tests are automatically executed in headless mode with:
- XML output for result reporting
- Artifact upload for test results
- Parallel execution across categories
- Failure tolerance with detailed reporting

## 📊 Test Results & Artifacts

### Available Artifacts
- **test-results:** JUnit XML files from test runs
- **linux-build:** Linux build artifacts
- **performance-results:** Performance test data
- **performance-baseline:** Performance tracking data

### Result Reporting
- JUnit XML format for GitHub integration
- Test Reporter action for PR comments
- Job summaries with detailed status
- Automatic issue creation for failures

## 🔧 Configuration Files

### Required Files
- `40k/.gutconfig.json` - GUT test configuration
- `40k/test_runner.cfg` - Test runner settings
- `40k/project.godot` - Godot project with GUT enabled

### Test Structure
```
40k/tests/
├── unit/              # Unit tests for autoloads and core classes
├── integration/       # Cross-system integration tests
├── network/           # Multiplayer and network tests
├── helpers/           # Test helper classes and data factories
└── disabled_tests/    # Tests temporarily disabled due to issues
```

## 🎯 Quality Gates

### Main Branch Protection
- All tests must pass
- Build must succeed
- Code quality checks must pass
- Security scan must pass

### Release Requirements
- Full test suite passes (100%)
- Multi-platform builds successful
- Performance within baselines
- Documentation up-to-date

## 🛡️ Security Features

### Automated Security Scanning
- Secret detection patterns
- File permission validation
- Dependency vulnerability checks
- Regular security audits

### Secure Practices
- No secrets in code
- Proper file permissions
- Artifact cleanup
- Access control via GitHub permissions

## 📈 Performance Monitoring

### Performance Baselines
- Test execution time tracking
- Memory usage monitoring
- Build time optimization
- Regression detection

### Alerts & Notifications
- Automatic issue creation for:
  - Test failures
  - Performance regressions
  - Security issues
  - Dependency updates needed

## 🔄 Maintenance Automation

### Automated Maintenance
- Weekly health checks
- Dependency update notifications
- Artifact cleanup
- Security audits
- Performance baseline updates

### Manual Maintenance
- Godot version updates
- GUT framework updates
- Workflow improvements
- Performance optimizations

## 📝 Usage Guidelines

### For Developers

1. **Before Pushing:**
   - Run tests locally
   - Ensure code quality
   - Update tests if needed

2. **Pull Requests:**
   - All tests must pass
   - Include test updates for new features
   - Document any breaking changes

3. **Releases:**
   - Use semantic versioning
   - Ensure all tests pass
   - Update release notes

### For Maintainers

1. **Weekly Reviews:**
   - Check maintenance reports
   - Address security issues
   - Monitor performance trends

2. **Dependency Updates:**
   - Test compatibility thoroughly
   - Update workflows if needed
   - Document breaking changes

3. **Workflow Updates:**
   - Keep actions up-to-date
   - Monitor for new best practices
   - Optimize performance

## 🚨 Troubleshooting

### Common Issues

**Tests Failing Locally but Passing in CI:**
- Check Godot version differences
- Verify test environment setup
- Check for timing-dependent tests

**Build Failures:**
- Verify export templates
- Check project configuration
- Validate asset dependencies

**Performance Issues:**
- Review test complexity
- Check for resource leaks
- Monitor system requirements

### Getting Help

1. Check workflow logs for detailed error messages
2. Review test output artifacts
3. Compare with successful runs
4. Check project documentation
5. Create issues for persistent problems

## 📋 Maintenance Checklist

### Monthly
- [ ] Review test coverage
- [ ] Update dependencies
- [ ] Check performance trends
- [ ] Review security reports

### Quarterly
- [ ] Godot version compatibility
- [ ] Workflow optimization
- [ ] Documentation updates
- [ ] Performance benchmarking

### Annually
- [ ] Full security audit
- [ ] CI/CD strategy review
- [ ] Tool evaluation
- [ ] Process improvements

---

This CI/CD setup provides comprehensive automated testing and deployment for the Warhammer 40k Godot game, ensuring code quality, security, and reliable releases.