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
    read -p "Press Enter to continue..."
    echo
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

# Function to setup Part 1
setup_part1() {
    print_header "Setting Up Part 1: Static MySQL Secret Rotation"
    cd part1-static-mysql
    ./mysql-setup.sh
    ./setup.sh
    cd ..
    print_success "Part 1 setup complete!"
}

# Function to setup Part 2
setup_part2() {
    print_header "Setting Up Part 2: Dynamic MySQL Credentials"
    cd part2-dynamic-mysql
    ./setup.sh
    cd ..
    print_success "Part 2 setup complete!"
}


# Function to run part 1 demo
run_part1() {
    setup_part1
    wait_for_input
    
    print_header "Part 1: Static MySQL Secret Rotation"
    echo "This demonstrates:"
    echo "• Vault-generated passwords using policies"
    echo "• Manual MySQL password rotation workflow"
    echo "• Target system updates coordination"
    echo "• Version history and rollback capabilities"
    echo "• The traditional approach to secret rotation"
    
    wait_for_input
    
    cd part1-static-mysql
    ./demo.sh
    cd ..
}

# Function to run part 2 demo
run_part2() {
    setup_part2
    wait_for_input
    
    print_header "Part 2: Dynamic MySQL Credentials"
    echo "This demonstrates:"
    echo "• On-demand credential generation" 
    echo "• Automatic cleanup after TTL expiration"
    echo "• No standing credentials in database"
    echo "• Perfect forward secrecy"
    echo "• The modern approach that eliminates rotation"
    
    wait_for_input
    
    cd part2-dynamic-mysql
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

# Function to show main menu
show_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             HashiCorp Vault Secret Rotation Demo            ║"
    echo "║                                                              ║"
    echo "║  🎯 Compare static rotation vs dynamic secrets              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${GREEN}Available Demo Parts:${NC}"
    echo "1. Part 1: Static MySQL Secret Rotation"
    echo "   • Vault-generated passwords using policies"
    echo "   • Manual MySQL password rotation workflow"
    echo "   • The traditional approach to secret rotation"
    echo
    echo "2. Part 2: Dynamic MySQL Credentials"
    echo "   • On-demand credential generation"
    echo "   • Automatic cleanup after TTL expiration"
    echo "   • The modern approach that eliminates rotation"
    echo
    echo "3. Demo Summary & Key Takeaways"
    echo "   • Complete comparison and recommendations"
    echo
    echo "4. Cleanup Demo Environment"
    echo "   • Stop containers and remove temporary files"
    echo
    echo "5. Exit"
    echo
}

# Main interactive menu
main() {
    # Check prerequisites once at startup
    check_prerequisites
    
    while true; do
        show_menu
        echo -n -e "${YELLOW}Select an option (1-5): ${NC}"
        read choice
        
        case $choice in
            1)
                run_part1
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            2)
                run_part2
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            3)
                show_summary
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            4)
                cleanup_demo
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            5)
                echo
                print_success "Thank you for using the Vault Secret Rotation demo!"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-5.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Handle script arguments
case "${1:-}" in
    "part1")
        check_prerequisites
        run_part1
        ;;
    "part2")
        check_prerequisites
        run_part2
        ;;
    "summary")
        show_summary
        ;;
    "cleanup")
        cleanup_demo
        ;;
    *)
        main
        ;;
esac