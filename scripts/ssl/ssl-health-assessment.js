#!/usr/bin/env node

/**
 * SSL Health Assessment Scanner
 * Version: 1.1.0
 */

const tls = require('tls');
const https = require('https');

class SSLHealthScanner {
    constructor(options = {}) {
        this.options = {
            timeout: options.timeout || 15000,
            verbose: options.verbose || false
        };
        
        this.protocols = ['TLSv1.3', 'TLSv1.2', 'TLSv1.1', 'TLSv1', 'SSLv3'];
    }

    async scan(hostname, port = 443) {
        console.log(`🔍 Starting SSL Health Assessment for ${hostname}:${port}`);
        console.log(`⏰ Scan started at: ${new Date().toISOString()}\n`);
        
        const startTime = Date.now();
        const results = {
            hostname,
            port,
            scanTime: new Date().toISOString(),
            overallGrade: 'F',
            certificates: {
                chain: [],
                length: 0,
                issues: [],
                daysUntilExpiry: null,
                hostnameMismatch: false
            },
            protocols: {},
            vulnerabilities: {},
            recommendations: [],
            connectionStatus: 'unknown'
        };

        try {
            // Test basic connectivity
            console.log('🔌 Testing basic connectivity...');
            const connectivityTest = await this.testBasicConnectivity(hostname, port);
            results.connectionStatus = connectivityTest.status;
            
            if (connectivityTest.status === 'failed') {
                results.error = connectivityTest.error;
                results.overallGrade = 'F';
                results.recommendations.push({
                    type: 'connectivity',
                    severity: 'critical',
                    message: 'Unable to establish SSL/TLS connection',
                    action: 'Check if the server is running and accessible on the specified port'
                });
                results.scanDuration = Date.now() - startTime;
                return results;
            }

            // Certificate Analysis
            console.log('📜 Analyzing certificates...');
            try {
                results.certificates = await this.analyzeCertificates(hostname, port);
            } catch (error) {
                console.log(`⚠️ Certificate analysis failed: ${error.message}`);
                results.certificates.issues.push(`Certificate analysis failed: ${error.message}`);
            }
            
            // Protocol Support Analysis
            console.log('🔐 Testing protocol support...');
            try {
                results.protocols = await this.analyzeProtocols(hostname, port);
            } catch (error) {
                console.log(`⚠️ Protocol analysis failed: ${error.message}`);
            }
            
            // Vulnerability Assessment
            console.log('🚨 Scanning for vulnerabilities...');
            try {
                results.vulnerabilities = await this.checkVulnerabilities(hostname, port);
            } catch (error) {
                console.log(`⚠️ Vulnerability scan failed: ${error.message}`);
            }
            
            // Calculate Overall Grade
            results.overallGrade = this.calculateGrade(results);
            
            // Generate Recommendations
            results.recommendations = this.generateRecommendations(results);
            
            results.scanDuration = Date.now() - startTime;
            console.log(`\n✅ Scan completed in ${results.scanDuration}ms`);
            
            return results;
            
        } catch (error) {
            console.error(`❌ Scan failed: ${error.message}`);
            results.error = error.message;
            results.scanDuration = Date.now() - startTime;
            return results;
        }
    }

    async testBasicConnectivity(hostname, port) {
        return new Promise((resolve) => {
            const options = {
                host: hostname,
                port: port,
                rejectUnauthorized: false,
                timeout: this.options.timeout,
                servername: hostname
            };

            const socket = tls.connect(options, () => {
                socket.end();
                resolve({ status: 'connected' });
            });

            socket.on('error', (error) => {
                resolve({ 
                    status: 'failed', 
                    error: error.message 
                });
            });

            socket.setTimeout(this.options.timeout, () => {
                socket.destroy();
                resolve({ 
                    status: 'failed', 
                    error: 'Connection timeout' 
                });
            });
        });
    }

    async analyzeCertificates(hostname, port) {
        return new Promise((resolve, reject) => {
            const options = {
                host: hostname,
                port: port,
                rejectUnauthorized: false,
                requestCert: true,
                agent: false,
                servername: hostname,
                timeout: this.options.timeout
            };

            const socket = tls.connect(options, () => {
                try {
                    const cert = socket.getPeerCertificate(true);
                    if (!cert || Object.keys(cert).length === 0) {
                        socket.end();
                        reject(new Error('No certificate received from server'));
                        return;
                    }
                    
                    const analysis = this.analyzeCertificate(cert, hostname);
                    socket.end();
                    resolve(analysis);
                } catch (error) {
                    socket.end();
                    reject(error);
                }
            });

            socket.on('error', (error) => {
                reject(new Error(`Certificate analysis failed: ${error.message}`));
            });

            socket.setTimeout(this.options.timeout, () => {
                socket.destroy();
                reject(new Error('Certificate analysis timeout'));
            });
        });
    }

    analyzeCertificate(cert, hostname) {
        const analysis = {
            chain: [cert],
            length: 1,
            issues: [],
            daysUntilExpiry: null,
            hostnameMismatch: false
        };

        // Check expiry
        const now = new Date();
        const validTo = new Date(cert.valid_to);
        analysis.daysUntilExpiry = Math.ceil((validTo - now) / (1000 * 60 * 60 * 24));
        
        if (validTo < now) {
            analysis.issues.push('Certificate has expired');
        } else if (analysis.daysUntilExpiry < 30) {
            analysis.issues.push(`Certificate expires in ${analysis.daysUntilExpiry} days`);
        }
        
        // Check hostname match
        if (!this.checkHostnameMatch(hostname, cert)) {
            analysis.hostnameMismatch = true;
            analysis.issues.push('Hostname mismatch');
        }

        return analysis;
    }

    checkHostnameMatch(hostname, cert) {
        try {
            const commonName = cert.subject?.CN;
            const altNames = cert.subjectaltname ? 
                cert.subjectaltname.split(', ').map(name => name.replace('DNS:', '')) : [];
            
            const allNames = [commonName, ...altNames].filter(Boolean);
            
            return allNames.some(name => {
                if (name === hostname) return true;
                if (name.startsWith('*.')) {
                    const wildcardDomain = name.slice(2);
                    return hostname.endsWith(wildcardDomain) && 
                           hostname.split('.').length === wildcardDomain.split('.').length + 1;
                }
                return false;
            });
        } catch (error) {
            return false;
        }
    }

    async analyzeProtocols(hostname, port) {
        const results = {};
        
        for (const protocol of this.protocols) {
            try {
                const supported = await this.testProtocol(hostname, port, protocol);
                results[protocol] = {
                    supported: supported,
                    grade: this.gradeProtocol(protocol, supported)
                };
            } catch (error) {
                results[protocol] = {
                    supported: false,
                    error: error.message
                };
            }
        }
        
        return results;
    }

    async testProtocol(hostname, port, protocol) {
        return new Promise((resolve) => {
            const options = {
                host: hostname,
                port: port,
                secureProtocol: this.mapProtocolToSecureProtocol(protocol),
                rejectUnauthorized: false,
                timeout: this.options.timeout,
                servername: hostname
            };

            const socket = tls.connect(options, () => {
                try {
                    const actualProtocol = socket.getProtocol();
                    socket.end();
                    resolve(actualProtocol === protocol);
                } catch (error) {
                    socket.end();
                    resolve(false);
                }
            });

            socket.on('error', () => {
                resolve(false);
            });

            socket.setTimeout(this.options.timeout, () => {
                socket.destroy();
                resolve(false);
            });
        });
    }

    mapProtocolToSecureProtocol(protocol) {
        const mapping = {
            'TLSv1.3': 'TLSv1_3_method',
            'TLSv1.2': 'TLSv1_2_method',
            'TLSv1.1': 'TLSv1_1_method',
            'TLSv1': 'TLSv1_method',
            'SSLv3': 'SSLv3_method'
        };
        return mapping[protocol] || 'TLS_method';
    }

    gradeProtocol(protocol, supported) {
        if (!supported) return 'N/A';
        
        const grades = {
            'TLSv1.3': 'A+',
            'TLSv1.2': 'A',
            'TLSv1.1': 'B',
            'TLSv1': 'C',
            'SSLv3': 'F'
        };
        
        return grades[protocol] || 'F';
    }

    async checkVulnerabilities(hostname, port) {
        const vulnerabilities = {
            poodle: false,
            freak: false
        };
        
        try {
            // Check for POODLE (SSLv3)
            const sslv3Supported = await this.testProtocol(hostname, port, 'SSLv3');
            vulnerabilities.poodle = sslv3Supported;
            
        } catch (error) {
            // Vulnerability check failed
        }

        return vulnerabilities;
    }

    calculateGrade(results) {
        let score = 0;
        let maxScore = 0;

        // Certificate scoring
        if (results.certificates.chain && results.certificates.chain.length > 0) {
            maxScore += 40;
            score += 20; // Base score for having certificates
            
            if (results.certificates.issues.length === 0) {
                score += 20;
            }
        }

        // Protocol scoring
        if (results.protocols['TLSv1.3'] && results.protocols['TLSv1.3'].supported) {
            maxScore += 30;
            score += 30;
        } else if (results.protocols['TLSv1.2'] && results.protocols['TLSv1.2'].supported) {
            maxScore += 30;
            score += 25;
        }

        // Vulnerability scoring
        const vulnCount = Object.values(results.vulnerabilities).filter(v => v === true).length;
        maxScore += 30;
        score += Math.max(0, 30 - (vulnCount * 15));

        // Calculate percentage
        const percentage = maxScore > 0 ? (score / maxScore) * 100 : 0;

        // Convert to letter grade
        if (percentage >= 90) return 'A+';
        if (percentage >= 80) return 'A';
        if (percentage >= 70) return 'B';
        if (percentage >= 60) return 'C';
        if (percentage >= 50) return 'D';
        return 'F';
    }

    generateRecommendations(results) {
        const recommendations = [];

        // Certificate recommendations
        if (results.certificates.issues.length > 0) {
            results.certificates.issues.forEach(issue => {
                recommendations.push({
                    type: 'certificate',
                    severity: 'high',
                    message: issue,
                    action: 'Fix certificate issues'
                });
            });
        }

        // Protocol recommendations
        if (!results.protocols['TLSv1.2'] || !results.protocols['TLSv1.2'].supported) {
            recommendations.push({
                type: 'protocol',
                severity: 'critical',
                message: 'TLS 1.2 not supported',
                action: 'Enable TLS 1.2 or higher'
            });
        }

        if (results.protocols['SSLv3'] && results.protocols['SSLv3'].supported) {
            recommendations.push({
                type: 'protocol',
                severity: 'high',
                message: 'SSLv3 is enabled (POODLE vulnerability)',
                action: 'Disable SSLv3'
            });
        }
        
        return recommendations;
    }

    formatResults(results) {
        console.log('\n📊 SSL HEALTH ASSESSMENT REPORT');
        console.log('═'.repeat(50));
        console.log(`🏆 Overall Grade: ${results.overallGrade}`);
        console.log(`🌐 Host: ${results.hostname}:${results.port}`);
        console.log(`⏱️  Scan Duration: ${results.scanDuration}ms`);
        console.log(`📅 Scan Time: ${results.scanTime}`);
        console.log(`🔌 Connection Status: ${results.connectionStatus}\n`);

        if (results.error) {
            console.log('❌ SCAN ERROR');
            console.log('-'.repeat(30));
            console.log(`Error: ${results.error}\n`);
        }

        // Certificate Analysis
        console.log('📜 CERTIFICATE ANALYSIS');
        console.log('-'.repeat(30));
        if (results.certificates.chain && results.certificates.chain.length > 0) {
            const leafCert = results.certificates.chain[0];
            console.log(`Subject: ${leafCert.subject?.CN || 'Unknown'}`);
            console.log(`Issuer: ${leafCert.issuer?.CN || 'Unknown'}`);
            console.log(`Valid Until: ${new Date(leafCert.valid_to).toISOString()}`);
            console.log(`Days Until Expiry: ${results.certificates.daysUntilExpiry}`);
        } else {
            console.log('❌ No certificates found');
        }
        
        if (results.certificates.issues.length > 0) {
            console.log(`❌ Issues: ${results.certificates.issues.join(', ')}`);
        }
        console.log('');

        // Protocol Support
        console.log('🔐 PROTOCOL SUPPORT');
        console.log('-'.repeat(30));
        Object.entries(results.protocols).forEach(([protocol, info]) => {
            const status = info.supported ? '✅' : '❌';
            const grade = info.grade || 'N/A';
            console.log(`${status} ${protocol}: ${grade}`);
        });
        console.log('');

        // Vulnerabilities
        if (Object.keys(results.vulnerabilities).length > 0) {
            console.log('🚨 VULNERABILITIES');
            console.log('-'.repeat(30));
            Object.entries(results.vulnerabilities).forEach(([vuln, present]) => {
                const status = present ? '❌ VULNERABLE' : '✅ SAFE';
                console.log(`${vuln.toUpperCase()}: ${status}`);
            });
            console.log('');
        }

        // Recommendations
        if (results.recommendations.length > 0) {
            console.log('💡 RECOMMENDATIONS');
            console.log('-'.repeat(30));
            results.recommendations.forEach((rec, index) => {
                console.log(`${index + 1}. [${rec.severity.toUpperCase()}] ${rec.message}`);
                console.log(`   Action: ${rec.action}\n`);
            });
        }

        return results;
    }
}

// CLI Usage
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.log('Usage: node ssl-health-assessment.js <hostname> [port]');
        console.log('Example: node ssl-health-assessment.js google.com 443');
        process.exit(1);
    }

    const hostname = args[0];
    const port = parseInt(args[1]) || 443;

    const scanner = new SSLHealthScanner();
    
    scanner.scan(hostname, port)
        .then(results => {
            scanner.formatResults(results);
            
            // Save results to JSON file
            const fs = require('fs');
            const filename = `ssl-report-${hostname}-${Date.now()}.json`;
            fs.writeFileSync(filename, JSON.stringify(results, null, 2));
            console.log(`\n📄 Report saved to: ${filename}`);
        })
        .catch(error => {
            console.error('❌ Scan failed:', error.message);
            process.exit(1);
        });
}

module.exports = SSLHealthScanner;
