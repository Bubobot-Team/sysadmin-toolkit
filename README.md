# DevOps Toolkit 🛠️

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![GitHub issues](https://img.shields.io/github/issues/bubobot-team/devops-toolkit)](https://github.com/bubobot-team/devops-toolkit/issues)
[![GitHub stars](https://img.shields.io/github/stars/bubobot-team/devops-toolkit)](https://github.com/bubobot-team/devops-toolkit/stargazers)

**Production-ready scripts and utilities for DevOps engineers and SysAdmins**

A curated collection of battle-tested automation scripts, monitoring utilities, and system maintenance tools designed for modern infrastructure management. Built by the community, for the community.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/bubobot-team/devops-toolkit.git
cd devops-toolkit

# Make scripts executable
chmod +x scripts/system-health/system-doctor.sh

# Run a basic system health check
./scripts/system-health/system-doctor.sh --verbose
```

## 📋 What's Inside

### 🏥 System Health Scripts
- **`system-doctor.sh`** - Comprehensive system health monitoring and auto-recovery
- **`resource-monitor.sh`** - Real-time resource monitoring with alerting
- **`cleanup-agent.sh`** - Intelligent log and cache cleanup utility

### 🔒 Security Tools
- **`audit-scanner.sh`** - Security audit and vulnerability scanning
- **`ssl-checker.sh`** - SSL certificate monitoring and expiry alerts

### 🚀 Deployment Utilities
- **`zero-downtime-deploy.sh`** - Blue-green deployment automation
- **`health-validator.sh`** - Post-deployment health validation

### 📊 Monitoring Integration
- **`service-watchdog.sh`** - Intelligent service monitoring and restart
- **`alert-processor.sh`** - Alert aggregation and intelligent routing

## 🎯 Featured Script: System Doctor

Our flagship script provides comprehensive system health monitoring and automated recovery:

```bash
# Basic health check with auto-fixes
./scripts/system-health/system-doctor.sh

# Check-only mode (no changes)
./scripts/system-health/system-doctor.sh --check-only

# Aggressive cleanup with service restarts
./scripts/system-health/system-doctor.sh --aggressive-clean --service-restart

# Generate JSON report for monitoring systems
./scripts/system-health/system-doctor.sh --report-json
```

### Key Features:
- ✅ **CPU, Memory, Disk monitoring** with intelligent thresholds
- ✅ **Service health checks** with automatic restart capabilities  
- ✅ **Smart log cleanup** with size-based triggers
- ✅ **Network connectivity validation**
- ✅ **JSON output** for integration with monitoring platforms
- ✅ **Zero-dependency** - runs on any Linux system

## 🔧 Integration Examples

### GitHub Actions CI/CD
```yaml
name: System Health Check
on: [push, schedule]
jobs:
  health-check:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v3
      - name: Run System Doctor
        run: ./scripts/system-health/system-doctor.sh --check-only --report-json
```

### Ansible Playbook
```yaml
- name: Run system health check
  command: ./system-doctor.sh --aggressive-clean
  register: health_result
  changed_when: health_result.rc != 0
```

## 📊 Monitoring Platform Integration

Our scripts are designed to integrate seamlessly with popular monitoring platforms:

- **Prometheus** - Metrics export via JSON output
- **Grafana** - Dashboard templates included
- **Bubobot** - Native integration for comprehensive monitoring
- **Datadog, New Relic** - Compatible output formats
- **PagerDuty, OpsGenie** - Alert routing capabilities

## 🏗️ Template Library

### Docker Compose Stacks
- **Monitoring Stack** (Prometheus + Grafana + AlertManager)
- **Logging Stack** (ELK/EFK stack with automation)
- **Security Stack** (Fail2ban + ModSecurity + monitoring)

### Systemd Services
- **Health Check Service** - Automated background monitoring
- **Cleanup Timer** - Scheduled maintenance tasks
- **Alert Service** - Real-time alerting daemon

### Cron Jobs
- **Daily Health Reports** - Automated system reporting
- **Weekly Cleanup** - Maintenance automation
- **Monthly Security Audit** - Automated security scans

## 🎓 Best Practices Guide

### System Monitoring
1. **Set appropriate thresholds** based on your workload patterns
2. **Monitor trends**, not just current values
3. **Implement gradual alerting** (warning → critical)
4. **Document your monitoring strategy**

### Automation Safety
1. **Always test in staging** before production deployment
2. **Implement rollback mechanisms**
3. **Use check-only mode** for validation
4. **Monitor automation effectiveness**

### Incident Response
1. **Automate common fixes** but escalate complex issues
2. **Log all automated actions** for audit trails
3. **Implement circuit breakers** to prevent automation loops
4. **Regular review** of automation effectiveness

## 🤝 Community & Support

### Join Our Community
- **Discord**: [Join our DevOps community](https://discord.gg/bubobot) 
- **GitHub Discussions**: Share experiences and get help
- **Blog**: [DevOps automation insights](https://blog.bubobot.com)

### Contributing
We welcome contributions! Check out our [Contributing Guide](CONTRIBUTING.md) to get started.

### Getting Help
1. **Documentation**: Check our [docs folder](docs/)
2. **GitHub Issues**: Report bugs or request features
3. **Community Discord**: Ask questions and share knowledge
4. **Stack Overflow**: Tag questions with `devops-toolkit`

## 📈 Used By

This toolkit is trusted by teams at:
- **Startups** building their first monitoring infrastructure
- **Scale-ups** automating operations for growth
- **Enterprises** standardizing DevOps practices
- **MSPs** managing multiple client environments

## 🛣️ Roadmap

### Q2 2025
- ✅ System health monitoring (system-doctor.sh)
- ⏳ Security audit tools
- ⏳ Container health monitoring
- ⏳ Database monitoring utilities

### Q3 2025
- ⏳ Kubernetes integration scripts
- ⏳ Cloud provider specific tools (AWS, GCP, Azure)
- ⏳ Advanced ML-based anomaly detection
- ⏳ Terraform integration modules

### Q4 2025
- ⏳ Mobile app for monitoring dashboards
- ⏳ Advanced alerting with ML
- ⏳ Compliance automation tools
- ⏳ Enterprise SSO integration

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Show Your Support

If this toolkit helps you, please give it a star! It helps others discover these tools and motivates us to keep improving.

---

**Built with ❤️ by the DevOps community**

*Looking for comprehensive monitoring solutions? Check out [Bubobot](https://bubobot.com) - the monitoring platform that integrates perfectly with these tools!*