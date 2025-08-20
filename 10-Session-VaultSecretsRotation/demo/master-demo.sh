#!/bin/bash

# Master Demo Script for Vault Secret Rotation
# This script orchestrates all three parts of the demo in the new order

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo "$(printf '=%.0s' {1..50})"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to wait for user input
wait_for_input() {
    echo
    read -p "Press Enter to continue to $1..."
    clear
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check Vault CLI
    if ! command -v vault &> /dev/null; then
        print_error "Vault CLI not found. Please install Vault."
        exit 1
    fi
    print_success "Vault CLI found: $(vault version | head -1)"
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install jq for JSON processing."
        exit 1
    fi
    print_success "jq found: $(jq --version)"
    
    # Check Docker (required for both parts now)
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Docker is required for the MySQL database used in both parts."
        echo
        echo "Please install Docker:"
        echo "  macOS: brew install docker"
        echo "  Ubuntu: sudo apt-get install docker.io"
        echo "  CentOS: sudo yum install docker"
        exit 1
    else
        print_success "Docker found: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    fi
    
    # Check if Vault is running
    if ! vault status >/dev/null 2>&1; then
        print_error "Vault is not running or not accessible."
        echo
        echo "To start Vault in dev mode, run:"
        echo "  vault server -dev -dev-root-token-id=myroot"
        echo
        echo "Then set the environment variables:"
        echo "  export VAULT_ADDR='http://127.0.0.1:8200'"
        echo "  export VAULT_TOKEN='myroot'"
        exit 1
    fi
    print_success "Vault is accessible"
    
    # Show Vault status
    echo
    vault status
}

# Function to run demo setup
run_setup() {
    print_header "Setting Up Demo Environment"
    
    # Part 1: Static MySQL rotation
    print_success "Setting up Part 1: Static MySQL Secret Rotation"
    cd part1-static-mysql
    ./mysql-setup.sh
    ./setup.sh
    cd ..
    
    # Part 2: Dynamic MySQL secrets  
    print_success "Setting up Part 2: Dynamic MySQL Credentials"
    cd part2-dynamic-mysql
    ./setup.sh
    cd ..
    
    # Part 3: Monitoring & Audit
    print_success "Setting up Part 3: Monitoring & Audit"
    cd part3-monitoring-audit
    ./setup.sh
    cd ..
    
    print_success "Demo environment setup complete!"
}

# Function to run part 1 demo
run_part1() {
    print_header "Part 1: Static MySQL Secret Rotation"
    echo "This demonstrates:"
    echo "• Vault-generated passwords using policies"
    echo "• Manual MySQL password rotation workflow"
    echo "• Target system updates coordination"
    echo "• Version history and rollback capabilities"
    echo "• The traditional approach to secret rotation"
    
    cd part1-static-mysql
    ./demo.sh
    cd ..
}

# Function to run part 2 demo
run_part2() {
    print_header "Part 2: Dynamic MySQL Credentials"
    echo "This demonstrates:"
    echo "• On-demand credential generation" 
    echo "• Automatic cleanup after TTL expiration"
    echo "• No standing credentials in database"
    echo "• Perfect forward secrecy"
    echo "• The modern approach that eliminates rotation"
    
    cd part2-dynamic-mysql
    ./demo.sh
    cd ..
}

# Function to run part 3 demo
run_part3() {
    print_header "Part 3: Monitoring & Audit"
    echo "This demonstrates:"
    echo "• Comprehensive audit logging"
    echo "• Real-time monitoring capabilities"
    echo "• Alert simulation and compliance"
    echo "• Complete operational visibility"
    
    cd part3-monitoring-audit
    ./demo.sh
    cd ..
}

# Function to show demo summary
show_summary() {
    print_header "Demo Summary & Key Takeaways"
    
    echo -e "\n${GREEN}🎯 What We Demonstrated:${NC}"
    echo "1. Static MySQL Rotation:"
    echo "   ✅ Vault-generated passwords with policies"
    echo "   ✅ Coordinated database and application updates"
    echo "   ✅ Version history for rollback capability"
    echo "   ⚠️  Still requires manual coordination"
    
    echo
    echo "2. Dynamic MySQL Credentials:"
    echo "   ✅ Just-in-time credential generation"
    echo "   ✅ Automatic cleanup and no credential sprawl"
    echo "   ✅ Perfect forward secrecy"
    echo "   ✅ No rotation needed (ephemeral by design)"
    
    echo
    echo "3. Monitoring & Audit:"
    echo "   ✅ Complete audit trail of all operations"
    echo "   ✅ Real-time monitoring and alerting"
    echo "   ✅ Compliance reporting capabilities"
    
    echo -e "\n${BLUE}🔄 The Clear Winner: Dynamic Secrets${NC}"
    echo "Static Rotation (Part 1):"
    echo "  • Good security improvement over never rotating"
    echo "  • Works with legacy applications"
    echo "  • Still requires operational overhead"
    echo "  • Credentials exist for extended periods"
    
    echo
    echo "Dynamic Secrets (Part 2):"
    echo "  • Ultimate security posture"
    echo "  • Zero operational rotation overhead"
    echo "  • Credentials exist only when needed"
    echo "  • Requires application Vault integration"
    
    echo -e "\n${YELLOW}💡 Implementation Strategy:${NC}"
    echo "1. Start with pilot application (low risk, high value)"
    echo "2. Use dynamic secrets for new applications"
    echo "3. Use static rotation for legacy/third-party integrations"
    echo "4. Enable comprehensive audit logging from day one"
    echo "5. Gradually migrate static to dynamic where possible"
    echo "6. Plan for organization-wide expansion"
    
    echo -e "\n${GREEN}🚀 Next Steps:${NC}"
    echo "• Set up proof-of-concept environment"
    echo "• Identify pilot applications and teams"
    echo "• Define success metrics and timeline"
    echo "• Plan integration with existing monitoring tools"
    echo "• Schedule follow-up sessions for specific use cases"
    
    echo
    print_success "Demo completed successfully!"
}

# Function to cleanup demo environment
cleanup_demo() {
    print_header "Demo Cleanup"
    
    echo "Cleaning up demo environment..."
    
    # Stop MySQL container if running
    if docker ps -q -f name=vault-mysql-demo >/dev/null 2>&1; then
        print_success "Stopping MySQL container..."
        docker stop vault-mysql-demo >/dev/null
        docker rm vault-mysql-demo >/dev/null
    fi
    
    # Clean up temporary files
    rm -rf part1-static-mysql/mysql-configs/*.backup.*
    
    print_success "Demo cleanup complete!"
}

# Main demo flow
main() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             HashiCorp Vault Secret Rotation Demo            ║"
    echo "║                                                              ║"
    echo "║  Part 1: Static MySQL Secret Rotation                       ║"
    echo "║  Part 2: Dynamic MySQL Credentials                          ║"  
    echo "║  Part 3: Monitoring & Audit                                 ║"
    echo "║                                                              ║"
    echo "║  🎯 Compare static rotation vs dynamic secrets              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    # Check prerequisites
    check_prerequisites
    wait_for_input "demo setup"
    
    # Run setup
    run_setup
    wait_for_input "Part 1 (Static MySQL Rotation)"
    
    # Run demos
    run_part1
    wait_for_input "Part 2 (Dynamic MySQL Credentials)"
    
    run_part2
    wait_for_input "Part 3 (Monitoring & Audit)"
    
    run_part3
    wait_for_input "demo summary"
    
    # Show summary
    show_summary
    
    # Ask about cleanup
    echo
    read -p "Would you like to clean up the demo environment? (y/N): " cleanup
    if [[ $cleanup =~ ^[Yy]$ ]]; then
        cleanup_demo
    fi
    
    echo
    print_success "Thank you for attending the Vault Secret Rotation demo!"
}

# Handle script arguments
case "${1:-}" in
    "setup")
        check_prerequisites
        run_setup
        ;;
    "part1")
        run_part1
        ;;
    "part2")
        run_part2
        ;;
    "part3")
        run_part3
        ;;
    "cleanup")
        cleanup_demo
        ;;
    *)
        main
        ;;
esac