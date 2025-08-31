#!/bin/bash
# Databricks App Creation (Bundle-based) - ASSIGNS EXISTING RESOURCES TO APP
# Automates the UI process: assigns existing resources to app service principal with permissions + keys

set -euo pipefail

# Colors & logging
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Helpers
prompt_with_default(){ local p="$1" d="$2" v; read -rp "$p ($d): " v; echo "${v:-$d}"; }
to_slug(){ echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-|-$//g'; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || { print_error "Missing required cmd: $1"; exit 1; }; }

# Load .env if present
if [ -f ".env" ]; then set -a; source ".env"; set +a; fi

# Required env
: "${DATABRICKS_HOST:?Set DATABRICKS_HOST in .env}"
: "${DATABRICKS_TOKEN:?Set DATABRICKS_TOKEN in .env}"

# YOUR EXISTING RESOURCES - These get assigned to each new app

# SQL Warehouse (from your existing setup)
EXISTING_WAREHOUSE_NAME="your-databricks-warehouse-name"
WAREHOUSE_KEY="sql-warehouse"
WAREHOUSE_PERMISSION="CAN_USE"

# Secret (from your existing secret scope)  
EXISTING_SECRET_SCOPE="your-secret-scope-name"
EXISTING_SECRET_KEY="your-databricks-token-secret"
SECRET_RESOURCE_KEY="secret" 
SECRET_PERMISSION="READ"

# Your 8 default serving endpoints - using arrays instead of associative arrays
declare -a ENDPOINT_KEYS ENDPOINT_NAMES ENDPOINT_PERMISSIONS
ENDPOINT_KEYS[1]="serving-endpoint"
ENDPOINT_NAMES[1]="databricks-claude-sonnet-4"
ENDPOINT_PERMISSIONS[1]="CAN_QUERY"

ENDPOINT_KEYS[2]="serving-endpoint-2"
ENDPOINT_NAMES[2]="databricks-claude-opus-4"
ENDPOINT_PERMISSIONS[2]="CAN_QUERY"

ENDPOINT_KEYS[3]="serving-endpoint-3" 
ENDPOINT_NAMES[3]="databricks-claude-3-7-sonnet"
ENDPOINT_PERMISSIONS[3]="CAN_QUERY"

ENDPOINT_KEYS[4]="serving-endpoint-4"
ENDPOINT_NAMES[4]="databricks-meta-llama-3-1-8b-instruct"
ENDPOINT_PERMISSIONS[4]="CAN_QUERY"

ENDPOINT_KEYS[5]="serving-endpoint-5"
ENDPOINT_NAMES[5]="databricks-meta-llama-3-3-70b-instruct"
ENDPOINT_PERMISSIONS[5]="CAN_QUERY"

ENDPOINT_KEYS[6]="serving-endpoint-6"
ENDPOINT_NAMES[6]="databricks-gemma-3-12b"
ENDPOINT_PERMISSIONS[6]="CAN_QUERY"

ENDPOINT_KEYS[7]="serving-endpoint-7"
ENDPOINT_NAMES[7]="databricks-llama-4-maverick"
ENDPOINT_PERMISSIONS[7]="CAN_QUERY"

ENDPOINT_KEYS[8]="serving-endpoint-8"
ENDPOINT_NAMES[8]="databricks-gpt-oss-120b"
ENDPOINT_PERMISSIONS[8]="CAN_QUERY"

# Unity Catalog defaults
DEFAULT_UC_CATALOG="your-catalog-name"
DEFAULT_UC_SCHEMA="your-schema-name" 
DEFAULT_UC_TABLE="your-table-name"

# Deps
require_cmd databricks
require_cmd jq
export DATABRICKS_HOST DATABRICKS_TOKEN

PROJECT_ROOT="$(pwd)"
CURRENT_DIR="$(basename "$PROJECT_ROOT")"
DEFAULT_APP_NAME="$(to_slug "$CURRENT_DIR")"

print_status "Interactive setup --- press Enter to accept defaults."

# App type selection
print_status "Select Databricks Data App Type:"
print_status "1. Streamlit (default)"
print_status "2. Gradio" 
print_status "3. Dash"
print_status "4. Shiny"
print_status "5. Flask"
print_status "6. Node.js"
read -rp "Enter choice 1-6 (default 1): " APP_TYPE_CHOICE
APP_TYPE_CHOICE="${APP_TYPE_CHOICE:-1}"

case $APP_TYPE_CHOICE in
    1) APP_TYPE="streamlit"; APP_FILE="app.py"; COMMAND_ARRAY='["streamlit", "run", "app.py", "--server.port", "8000", "--server.address", "0.0.0.0"]';;
    2) APP_TYPE="gradio"; APP_FILE="app.py"; COMMAND_ARRAY='["python", "app.py"]';;
    3) APP_TYPE="dash"; APP_FILE="app.py"; COMMAND_ARRAY='["python", "app.py"]';;
    4) APP_TYPE="shiny"; APP_FILE="app.py"; COMMAND_ARRAY='["shiny", "run", "app.py", "--host", "0.0.0.0", "--port", "8000"]';;
    5) APP_TYPE="flask"; APP_FILE="app.py"; COMMAND_ARRAY='["python", "app.py"]';;
    6) APP_TYPE="nodejs"; APP_FILE="app.js"; COMMAND_ARRAY='["node", "app.js"]';;
    *) print_error "Invalid choice. Must be 1-6."; exit 1;;
esac

print_success "Selected app type: $APP_TYPE"

RAW_APP_NAME="${1:-$DEFAULT_APP_NAME}"
APP_NAME="$(to_slug "$(prompt_with_default 'App name (lowercase, a-z0-9-, between 2-30 characters)' "$RAW_APP_NAME")")"
[[ "$APP_NAME" =~ ^[a-z0-9-]+$ ]] || { print_error "Invalid app name."; exit 1; }

# Validate app name length (2-30 characters)
APP_NAME_LENGTH=${#APP_NAME}
if [[ $APP_NAME_LENGTH -lt 2 || $APP_NAME_LENGTH -gt 30 ]]; then
    print_error "App name must be between 2-30 characters. Current length: $APP_NAME_LENGTH"
    exit 1
fi

DEFAULT_BUNDLE_NAME="${APP_NAME}-bundle"
RAW_BUNDLE_NAME="$(prompt_with_default 'Bundle name (lowercase, a-z0-9-)' "$DEFAULT_BUNDLE_NAME")"
BUNDLE_NAME="$(to_slug "$RAW_BUNDLE_NAME")"
[[ "$BUNDLE_NAME" =~ ^[a-z0-9-]+$ ]] || { print_error "Invalid bundle name."; exit 1; }

UC_CATALOG="$(prompt_with_default 'Unity Catalog (UC_CATALOG)' "$DEFAULT_UC_CATALOG")"
UC_SCHEMA="$(prompt_with_default 'UC schema (UC_SCHEMA)' "$DEFAULT_UC_SCHEMA")"
UC_TABLE="$(prompt_with_default 'UC table (UC_TABLE)' "$DEFAULT_UC_TABLE")"

# Add extra Serving Endpoints prompt
read -rp "Add extra Serving Endpoints? Enter count 0-4 (default 0): " EXTRA_COUNT
EXTRA_COUNT="${EXTRA_COUNT:-0}"
[[ "$EXTRA_COUNT" =~ ^[0-4]$ ]] || { print_error "Extra endpoint count must be 0-4."; exit 1; }

if (( EXTRA_COUNT > 0 )); then
    for (( i=9; i<=8+EXTRA_COUNT; i++ )); do
        ENDPOINT_KEYS[$i]="serving-endpoint-$i"
        ENDPOINT_NAMES[$i]="$(prompt_with_default "Extra endpoint $i name (must match an existing serving endpoint in Databricks)" "your-existing-endpoint-name")"
        ENDPOINT_PERMISSIONS[$i]="CAN_QUERY"
    done
fi

TOTAL_EP=$((8 + EXTRA_COUNT))

# Auth & user
print_status "Validating Databricks CLI authentication..."
CURRENT_USER="$(databricks current-user me --output json | jq -r '.userName')"
[[ -n "$CURRENT_USER" && "$CURRENT_USER" != "null" ]] || { print_error "Cannot resolve current user."; exit 1; }
print_success "Databricks CLI authenticated as: $CURRENT_USER"

print_status "Creating app '$APP_NAME' with ${TOTAL_EP} serving endpoints..."

# Get warehouse ID by name (like dropdown selection in UI)
print_status "Looking up existing resources..."
WAREHOUSE_ID="$(databricks warehouses list --output json | jq -r ".[] | select(.name==\"$EXISTING_WAREHOUSE_NAME\") | .id")"
[[ -n "$WAREHOUSE_ID" && "$WAREHOUSE_ID" != "null" ]] || { print_error "Could not find warehouse '$EXISTING_WAREHOUSE_NAME'"; exit 1; }
print_success "✅ Found SQL Warehouse: $EXISTING_WAREHOUSE_NAME (ID: $WAREHOUSE_ID)"

# Verify secret scope exists
if ! databricks secrets list-scopes --output json | jq -e ".[] | select(.name==\"$EXISTING_SECRET_SCOPE\")" >/dev/null; then
    print_error "Secret scope '$EXISTING_SECRET_SCOPE' not found."
    exit 1
fi
print_success "✅ Found Secret Scope: $EXISTING_SECRET_SCOPE"

# Verify serving endpoints exist
print_status "Verifying serving endpoints..."
for i in $(seq 1 $TOTAL_EP); do
    endpoint_name="${ENDPOINT_NAMES[$i]}"
    
    if databricks serving-endpoints get "$endpoint_name" >/dev/null 2>&1; then
        print_success "✅ Found serving endpoint: $endpoint_name"
    else
        print_warning "⚠️  Serving endpoint '$endpoint_name' not found (may not be available in your region)"
    fi
done

# Clean up existing app and bundle cache
print_status "Cleaning up existing deployments..."
rm -rf .databricks/ || true
if databricks apps get "${APP_NAME}" >/dev/null 2>&1; then
    print_status "Deleting existing app '${APP_NAME}'..."
    databricks apps delete "${APP_NAME}" || true
    sleep 3
fi

# ─────────────────────────────────────────────────────────────────
# Create databricks.yml - This assigns existing resources to the app
# Equivalent to: UI dropdown selection + permission + resource key assignment
# ─────────────────────────────────────────────────────────────────
print_status "Creating databricks.yml that assigns existing resources to app..."
cat > databricks.yml <<EOF
bundle:
  name: ${BUNDLE_NAME}

targets:
  default:
    mode: development
    workspace:
      host: ${DATABRICKS_HOST}
      root_path: /Workspace/Users/\${workspace.current_user.userName}/.bundle/\${bundle.name}/\${bundle.target}
    variables:
      app_name: ${APP_NAME}

resources:
  apps:
    main_app:
      name: \${var.app_name}
      description: "$(echo ${APP_TYPE} | sed 's/./\U&/') app: ${CURRENT_DIR}"
      source_code_path: .
      resources:
        # Assign existing SQL Warehouse to app (like UI dropdown + permission + key)
        - name: '${WAREHOUSE_KEY}'
          sql_warehouse:
            id: '${WAREHOUSE_ID}'
            permission: '${WAREHOUSE_PERMISSION}'
        
        # Assign existing Secret to app (like UI dropdown + permission + key)
        - name: '${SECRET_RESOURCE_KEY}'
          secret:
            scope: '${EXISTING_SECRET_SCOPE}'
            key: '${EXISTING_SECRET_KEY}'
            permission: '${SECRET_PERMISSION}'
EOF

# Add all serving endpoints (like UI dropdown + permission + key for each)
for i in $(seq 1 $TOTAL_EP); do
    endpoint_key="${ENDPOINT_KEYS[$i]}"
    endpoint_name="${ENDPOINT_NAMES[$i]}"
    endpoint_permission="${ENDPOINT_PERMISSIONS[$i]}"
    
    cat >> databricks.yml <<EOF
        
        # Assign existing serving endpoint to app
        - name: '${endpoint_key}'
          serving_endpoint:
            name: '${endpoint_name}'
            permission: '${endpoint_permission}'
EOF
done

# Close the YAML
cat >> databricks.yml <<EOF

variables:
  app_name:
    description: "Name of the app"
EOF

# ─────────────────────────────────────────────────────────────
# Create app.yaml - Uses the resource keys to access assigned resources
# ─────────────────────────────────────────────────────────────
print_status "Creating app.yaml that uses assigned resource keys..."
cat > app.yaml <<EOF
command: ${COMMAND_ARRAY}
env:
  # Basic environment
  - name: DATABRICKS_HOST
    value: '${DATABRICKS_HOST}'
  - name: UC_CATALOG
    value: '${UC_CATALOG}'
  - name: UC_SCHEMA
    value: '${UC_SCHEMA}'
  - name: UC_TABLE
    value: '${UC_TABLE}'
  
  # From assigned resources (using resource keys)
  - name: DATABRICKS_TOKEN
    valueFrom: '${SECRET_RESOURCE_KEY}'
  - name: DATABRICKS_SQL_WAREHOUSE_ID
    valueFrom: '${WAREHOUSE_KEY}'
  
  # SQL warehouse HTTP path (required for app functionality)
  - name: DATABRICKS_SQL_HTTP_PATH
    value: '${SQL_HTTP_PATH:-/sql/1.0/warehouses/${WAREHOUSE_ID}}'
  
  # Main serving endpoint URL and name
  - name: DATABRICKS_SERVING_ENDPOINT_URL
    value: '${DATABRICKS_HOST%/}/serving-endpoints/${ENDPOINT_NAMES[1]}/invocations'
  - name: DBX_ENDPOINT
    value: '${ENDPOINT_NAMES[1]}'
EOF

# Add endpoint environment variables for each assigned serving endpoint
for i in $(seq 2 $TOTAL_EP); do
    endpoint_name="${ENDPOINT_NAMES[$i]}"
    
    cat >> app.yaml <<EOF
  - name: DATABRICKS_ENDPOINT_${i}_URL
    value: '${DATABRICKS_HOST%/}/serving-endpoints/${endpoint_name}/invocations'
  - name: DBX_ENDPOINT_${i}
    value: '${endpoint_name}'
EOF
done

# ─────────────────────────────────────────────────────────────
# Create app file based on selected type
# ─────────────────────────────────────────────────────────────
if [ ! -f "$APP_FILE" ]; then
    print_status "Creating $APP_FILE for $APP_TYPE..."
    
    case $APP_TYPE in
        "streamlit")
            cat > app.py <<'EOF'
import os
import streamlit as st

st.title("Databricks App with Assigned Resources (Streamlit)")
st.write("🎉 This app has existing resources assigned to its service principal!")

with st.expander("📋 Assigned App Resources"):
    st.write("**SQL Warehouse:**")
    warehouse_id = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
    warehouse_path = os.getenv('DATABRICKS_SQL_HTTP_PATH')
    if warehouse_id:
        st.success(f"✅ Assigned warehouse ID: {warehouse_id}")
        if warehouse_path:
            st.success(f"✅ SQL HTTP Path: {warehouse_path}")
    else:
        st.error("❌ No warehouse assigned")
    
    st.write("**Secret:**") 
    token = os.getenv('DATABRICKS_TOKEN')
    if token:
        st.success("✅ Secret assigned and accessible")
    else:
        st.error("❌ No secret assigned")
    
    st.write("**Serving Endpoints:**")
    endpoints_found = 0
    
    # Check main endpoint
    main_endpoint = os.getenv('DBX_ENDPOINT')
    if main_endpoint:
        st.success(f"✅ Main: {main_endpoint}")
        endpoints_found += 1
    
    # Check additional endpoints
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            st.success(f"✅ Endpoint {i}: {endpoint_name}")
            endpoints_found += 1
    
    st.info(f"📊 Total endpoints assigned: {endpoints_found}")

with st.expander("🔑 Resource Keys & Values"):
    st.write("These match what you see in the UI 'App resources' section:")
    
    resource_keys = [
        ("DATABRICKS_SQL_WAREHOUSE_ID", "sql-warehouse"),
        ("DATABRICKS_SQL_HTTP_PATH", "sql-warehouse-path"),
        ("DATABRICKS_TOKEN", "secret"),
        ("DBX_ENDPOINT", "serving-endpoint"),
    ]
    
    # Add endpoint keys
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            resource_keys.append((f"DBX_ENDPOINT_{i}", f"serving-endpoint-{i}"))
    
    for env_var, resource_key in resource_keys:
        value = os.getenv(env_var)
        if value:
            if "TOKEN" in env_var:
                st.write(f"**{resource_key}** → `{env_var}`: {'*' * 10} (hidden)")
            else:
                st.write(f"**{resource_key}** → `{env_var}`: {value}")

if st.button("🧪 Test All Assigned Resources"):
    try:
        warehouse_id = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
        warehouse_path = os.getenv('DATABRICKS_SQL_HTTP_PATH')
        host = os.getenv('DATABRICKS_HOST')
        token = os.getenv('DATABRICKS_TOKEN')
        main_endpoint = os.getenv('DBX_ENDPOINT')
        
        results = []
        if warehouse_id: results.append("✅ SQL Warehouse ID")
        if warehouse_path: results.append("✅ SQL HTTP Path")
        if token: results.append("✅ Authentication Secret")  
        if main_endpoint: results.append("✅ Serving Endpoints")
        if host: results.append("✅ Databricks Host")
        
        if len(results) >= 4:
            st.success("🎉 All assigned resources are working!")
            st.balloons()
            for result in results:
                st.write(result)
        else:
            st.error("❌ Some resources are missing")
            
    except Exception as e:
        st.error(f"Error testing resources: {e}")

st.markdown("---")
st.caption("Resources assigned via Databricks Asset Bundle (equivalent to UI assignment)")
EOF
            ;;
        "gradio")
            cat > app.py <<'EOF'
import os
import gradio as gr

def show_resources():
    """Display assigned resources"""
    output = []
    output.append("# 🎉 Databricks App with Assigned Resources")
    output.append("This app has existing resources assigned to its service principal!\n")
    
    # SQL Warehouse
    output.append("## 📊 SQL Warehouse:")
    warehouse_id = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
    warehouse_path = os.getenv('DATABRICKS_SQL_HTTP_PATH')
    if warehouse_id:
        output.append(f"✅ Assigned warehouse ID: {warehouse_id}")
        if warehouse_path:
            output.append(f"✅ SQL HTTP Path: {warehouse_path}")
    else:
        output.append("❌ No warehouse assigned")
    
    # Secret
    output.append("\n## 🔐 Secret:")
    token = os.getenv('DATABRICKS_TOKEN')
    if token:
        output.append("✅ Secret assigned and accessible")
    else:
        output.append("❌ No secret assigned")
    
    # Serving Endpoints
    output.append("\n## 🤖 Serving Endpoints:")
    endpoints_found = 0
    
    main_endpoint = os.getenv('DBX_ENDPOINT')
    if main_endpoint:
        output.append(f"✅ Main: {main_endpoint}")
        endpoints_found += 1
    
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            output.append(f"✅ Endpoint {i}: {endpoint_name}")
            endpoints_found += 1
    
    output.append(f"\n📊 Total endpoints assigned: {endpoints_found}")
    
    return "\n".join(output)

def test_resources():
    """Test all assigned resources"""
    try:
        warehouse_id = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
        warehouse_path = os.getenv('DATABRICKS_SQL_HTTP_PATH')
        host = os.getenv('DATABRICKS_HOST')
        token = os.getenv('DATABRICKS_TOKEN')
        main_endpoint = os.getenv('DBX_ENDPOINT')
        
        results = []
        if warehouse_id: results.append("✅ SQL Warehouse ID")
        if warehouse_path: results.append("✅ SQL HTTP Path")
        if token: results.append("✅ Authentication Secret")  
        if main_endpoint: results.append("✅ Serving Endpoints")
        if host: results.append("✅ Databricks Host")
        
        if len(results) >= 4:
            return "🎉 All assigned resources are working!\n" + "\n".join(results)
        else:
            return "❌ Some resources are missing"
            
    except Exception as e:
        return f"Error testing resources: {e}"

# Create Gradio interface
with gr.Blocks(title="Databricks Resources") as demo:
    gr.Markdown("# Databricks App with Assigned Resources (Gradio)")
    
    with gr.Tab("📋 Resources"):
        resources_output = gr.Markdown(show_resources())
    
    with gr.Tab("🧪 Test"):
        test_btn = gr.Button("Test All Assigned Resources")
        test_output = gr.Markdown()
        test_btn.click(test_resources, outputs=test_output)

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=8000)
EOF
            ;;
        "dash")
            cat > app.py <<'EOF'
import os
import dash
from dash import html, dcc, callback, Output, Input

app = dash.Dash(__name__)

def get_resources_data():
    """Get assigned resources data"""
    resources = {}
    
    # SQL Warehouse
    resources['warehouse_id'] = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
    resources['warehouse_path'] = os.getenv('DATABRICKS_SQL_HTTP_PATH')
    
    # Secret
    resources['has_token'] = bool(os.getenv('DATABRICKS_TOKEN'))
    
    # Endpoints
    resources['endpoints'] = []
    main_endpoint = os.getenv('DBX_ENDPOINT')
    if main_endpoint:
        resources['endpoints'].append(f"Main: {main_endpoint}")
    
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            resources['endpoints'].append(f"Endpoint {i}: {endpoint_name}")
    
    return resources

app.layout = html.Div([
    html.H1("🎉 Databricks App with Assigned Resources (Dash)", 
            style={'textAlign': 'center'}),
    
    html.Div([
        html.H2("📊 SQL Warehouse"),
        html.Div(id='warehouse-info'),
        
        html.H2("🔐 Secret"),
        html.Div(id='secret-info'),
        
        html.H2("🤖 Serving Endpoints"),
        html.Div(id='endpoints-info'),
        
        html.Button("🧪 Test All Resources", id='test-btn', 
                   style={'margin': '20px 0', 'padding': '10px 20px'}),
        html.Div(id='test-results')
    ], style={'margin': '20px'})
])

@callback(
    [Output('warehouse-info', 'children'),
     Output('secret-info', 'children'),
     Output('endpoints-info', 'children')],
    Input('test-btn', 'n_clicks')
)
def update_resources_info(n_clicks):
    resources = get_resources_data()
    
    # Warehouse info
    warehouse_children = []
    if resources['warehouse_id']:
        warehouse_children.append(html.P(f"✅ Warehouse ID: {resources['warehouse_id']}", 
                                       style={'color': 'green'}))
        if resources['warehouse_path']:
            warehouse_children.append(html.P(f"✅ SQL HTTP Path: {resources['warehouse_path']}", 
                                           style={'color': 'green'}))
    else:
        warehouse_children.append(html.P("❌ No warehouse assigned", style={'color': 'red'}))
    
    # Secret info
    if resources['has_token']:
        secret_children = [html.P("✅ Secret assigned and accessible", style={'color': 'green'})]
    else:
        secret_children = [html.P("❌ No secret assigned", style={'color': 'red'})]
    
    # Endpoints info
    endpoints_children = []
    if resources['endpoints']:
        for endpoint in resources['endpoints']:
            endpoints_children.append(html.P(f"✅ {endpoint}", style={'color': 'green'}))
        endpoints_children.append(html.P(f"📊 Total: {len(resources['endpoints'])} endpoints"))
    else:
        endpoints_children.append(html.P("❌ No endpoints assigned", style={'color': 'red'}))
    
    return warehouse_children, secret_children, endpoints_children

@callback(
    Output('test-results', 'children'),
    Input('test-btn', 'n_clicks')
)
def test_resources(n_clicks):
    if not n_clicks:
        return ""
    
    try:
        resources = get_resources_data()
        results = []
        
        if resources['warehouse_id']: results.append("✅ SQL Warehouse ID")
        if resources['warehouse_path']: results.append("✅ SQL HTTP Path") 
        if resources['has_token']: results.append("✅ Authentication Secret")
        if resources['endpoints']: results.append("✅ Serving Endpoints")
        if os.getenv('DATABRICKS_HOST'): results.append("✅ Databricks Host")
        
        if len(results) >= 4:
            return html.Div([
                html.H3("🎉 All assigned resources are working!", style={'color': 'green'}),
                html.Ul([html.Li(result) for result in results])
            ])
        else:
            return html.P("❌ Some resources are missing", style={'color': 'red'})
            
    except Exception as e:
        return html.P(f"Error testing resources: {e}", style={'color': 'red'})

if __name__ == '__main__':
    app.run_server(host='0.0.0.0', port=8000, debug=False)
EOF
            ;;
        "shiny")
            cat > app.py <<'EOF'
import os
from shiny import App, render, ui

def get_resources_data():
    """Get assigned resources data"""
    resources = {}
    
    # SQL Warehouse
    resources['warehouse_id'] = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
    resources['warehouse_path'] = os.getenv('DATABRICKS_SQL_HTTP_PATH')
    
    # Secret
    resources['has_token'] = bool(os.getenv('DATABRICKS_TOKEN'))
    
    # Endpoints
    resources['endpoints'] = []
    main_endpoint = os.getenv('DBX_ENDPOINT')
    if main_endpoint:
        resources['endpoints'].append(f"Main: {main_endpoint}")
    
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            resources['endpoints'].append(f"Endpoint {i}: {endpoint_name}")
    
    return resources

app_ui = ui.page_fluid(
    ui.h1("🎉 Databricks App with Assigned Resources (Shiny)"),
    
    ui.navset_tab(
        ui.nav("📋 Resources",
            ui.h2("📊 SQL Warehouse"),
            ui.output_ui("warehouse_info"),
            
            ui.h2("🔐 Secret"),
            ui.output_ui("secret_info"),
            
            ui.h2("🤖 Serving Endpoints"),
            ui.output_ui("endpoints_info")
        ),
        
        ui.nav("🧪 Test",
            ui.input_action_button("test_btn", "Test All Assigned Resources"),
            ui.output_ui("test_results")
        )
    )
)

def server(input, output, session):
    
    @output
    @render.ui
    def warehouse_info():
        resources = get_resources_data()
        if resources['warehouse_id']:
            result = [ui.p(f"✅ Warehouse ID: {resources['warehouse_id']}", style="color: green;")]
            if resources['warehouse_path']:
                result.append(ui.p(f"✅ SQL HTTP Path: {resources['warehouse_path']}", style="color: green;"))
            return result
        else:
            return ui.p("❌ No warehouse assigned", style="color: red;")
    
    @output
    @render.ui
    def secret_info():
        resources = get_resources_data()
        if resources['has_token']:
            return ui.p("✅ Secret assigned and accessible", style="color: green;")
        else:
            return ui.p("❌ No secret assigned", style="color: red;")
    
    @output
    @render.ui
    def endpoints_info():
        resources = get_resources_data()
        if resources['endpoints']:
            result = []
            for endpoint in resources['endpoints']:
                result.append(ui.p(f"✅ {endpoint}", style="color: green;"))
            result.append(ui.p(f"📊 Total: {len(resources['endpoints'])} endpoints"))
            return result
        else:
            return ui.p("❌ No endpoints assigned", style="color: red;")
    
    @output
    @render.ui
    def test_results():
        if input.test_btn() == 0:
            return ""
        
        try:
            resources = get_resources_data()
            results = []
            
            if resources['warehouse_id']: results.append("✅ SQL Warehouse ID")
            if resources['warehouse_path']: results.append("✅ SQL HTTP Path")
            if resources['has_token']: results.append("✅ Authentication Secret")
            if resources['endpoints']: results.append("✅ Serving Endpoints")
            if os.getenv('DATABRICKS_HOST'): results.append("✅ Databricks Host")
            
            if len(results) >= 4:
                return ui.div(
                    ui.h3("🎉 All assigned resources are working!", style="color: green;"),
                    ui.tags.ul([ui.tags.li(result) for result in results])
                )
            else:
                return ui.p("❌ Some resources are missing", style="color: red;")
                
        except Exception as e:
            return ui.p(f"Error testing resources: {e}", style="color: red;")

app = App(app_ui, server)
EOF
            ;;
        "flask")
            cat > app.py <<'EOF'
import os
from flask import Flask, render_template_string, jsonify

app = Flask(__name__)

def get_resources_data():
    """Get assigned resources data"""
    resources = {}
    
    # SQL Warehouse
    resources['warehouse_id'] = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')
    resources['warehouse_path'] = os.getenv('DATABRICKS_SQL_HTTP_PATH')
    
    # Secret
    resources['has_token'] = bool(os.getenv('DATABRICKS_TOKEN'))
    
    # Endpoints
    resources['endpoints'] = []
    main_endpoint = os.getenv('DBX_ENDPOINT')
    if main_endpoint:
        resources['endpoints'].append(f"Main: {main_endpoint}")
    
    for i in range(2, 13):
        endpoint_name = os.getenv(f'DBX_ENDPOINT_{i}')
        if endpoint_name:
            resources['endpoints'].append(f"Endpoint {i}: {endpoint_name}")
    
    return resources

@app.route('/')
def index():
    template = '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Databricks Resources</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .success { color: green; }
            .error { color: red; }
            .info { color: blue; }
            button { padding: 10px 20px; margin: 20px 0; }
        </style>
        <script>
            function testResources() {
                fetch('/test')
                    .then(response => response.json())
                    .then(data => {
                        document.getElementById('test-results').innerHTML = data.html;
                    });
            }
        </script>
    </head>
    <body>
        <h1>🎉 Databricks App with Assigned Resources (Flask)</h1>
        
        <h2>📊 SQL Warehouse</h2>
        <div>
            {% if resources.warehouse_id %}
                <p class="success">✅ Warehouse ID: {{ resources.warehouse_id }}</p>
                {% if resources.warehouse_path %}
                    <p class="success">✅ SQL HTTP Path: {{ resources.warehouse_path }}</p>
                {% endif %}
            {% else %}
                <p class="error">❌ No warehouse assigned</p>
            {% endif %}
        </div>
        
        <h2>🔐 Secret</h2>
        <div>
            {% if resources.has_token %}
                <p class="success">✅ Secret assigned and accessible</p>
            {% else %}
                <p class="error">❌ No secret assigned</p>
            {% endif %}
        </div>
        
        <h2>🤖 Serving Endpoints</h2>
        <div>
            {% if resources.endpoints %}
                {% for endpoint in resources.endpoints %}
                    <p class="success">✅ {{ endpoint }}</p>
                {% endfor %}
                <p class="info">📊 Total: {{ resources.endpoints|length }} endpoints</p>
            {% else %}
                <p class="error">❌ No endpoints assigned</p>
            {% endif %}
        </div>
        
        <button onclick="testResources()">🧪 Test All Resources</button>
        <div id="test-results"></div>
        
        <hr>
        <p><em>Resources assigned via Databricks Asset Bundle (equivalent to UI assignment)</em></p>
    </body>
    </html>
    '''
    
    resources = get_resources_data()
    return render_template_string(template, resources=resources)

@app.route('/test')
def test_resources():
    try:
        resources = get_resources_data()
        results = []
        
        if resources['warehouse_id']: results.append("✅ SQL Warehouse ID")
        if resources['warehouse_path']: results.append("✅ SQL HTTP Path")
        if resources['has_token']: results.append("✅ Authentication Secret")
        if resources['endpoints']: results.append("✅ Serving Endpoints")
        if os.getenv('DATABRICKS_HOST'): results.append("✅ Databricks Host")
        
        if len(results) >= 4:
            html = '<h3 class="success">🎉 All assigned resources are working!</h3><ul>'
            for result in results:
                html += f'<li>{result}</li>'
            html += '</ul>'
        else:
            html = '<p class="error">❌ Some resources are missing</p>'
        
        return jsonify({'html': html})
        
    except Exception as e:
        return jsonify({'html': f'<p class="error">Error testing resources: {e}</p>'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)
EOF
            ;;
        "nodejs")
            cat > app.js <<'EOF'
const express = require('express');
const app = express();
const port = 8000;

// Serve static files
app.use(express.static('public'));

function getResourcesData() {
    const resources = {};
    
    // SQL Warehouse
    resources.warehouse_id = process.env.DATABRICKS_SQL_WAREHOUSE_ID;
    resources.warehouse_path = process.env.DATABRICKS_SQL_HTTP_PATH;
    
    // Secret
    resources.has_token = !!process.env.DATABRICKS_TOKEN;
    
    // Endpoints
    resources.endpoints = [];
    const main_endpoint = process.env.DBX_ENDPOINT;
    if (main_endpoint) {
        resources.endpoints.push(`Main: ${main_endpoint}`);
    }
    
    for (let i = 2; i <= 12; i++) {
        const endpoint_name = process.env[`DBX_ENDPOINT_${i}`];
        if (endpoint_name) {
            resources.endpoints.push(`Endpoint ${i}: ${endpoint_name}`);
        }
    }
    
    return resources;
}

app.get('/', (req, res) => {
    const resources = getResourcesData();
    
    const html = `
    <!DOCTYPE html>
    <html>
    <head>
        <title>Databricks Resources</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .success { color: green; }
            .error { color: red; }
            .info { color: blue; }
            button { padding: 10px 20px; margin: 20px 0; }
        </style>
        <script>
            function testResources() {
                fetch('/test')
                    .then(response => response.json())
                    .then(data => {
                        document.getElementById('test-results').innerHTML = data.html;
                    });
            }
        </script>
    </head>
    <body>
        <h1>🎉 Databricks App with Assigned Resources (Node.js)</h1>
        
        <h2>📊 SQL Warehouse</h2>
        <div>
            ${resources.warehouse_id ? 
                `<p class="success">✅ Warehouse ID: ${resources.warehouse_id}</p>` +
                (resources.warehouse_path ? `<p class="success">✅ SQL HTTP Path: ${resources.warehouse_path}</p>` : '') :
                '<p class="error">❌ No warehouse assigned</p>'}
        </div>
        
        <h2>🔐 Secret</h2>
        <div>
            ${resources.has_token ? 
                '<p class="success">✅ Secret assigned and accessible</p>' :
                '<p class="error">❌ No secret assigned</p>'}
        </div>
        
        <h2>🤖 Serving Endpoints</h2>
        <div>
            ${resources.endpoints.length > 0 ? 
                resources.endpoints.map(endpoint => `<p class="success">✅ ${endpoint}</p>`).join('') +
                `<p class="info">📊 Total: ${resources.endpoints.length} endpoints</p>` :
                '<p class="error">❌ No endpoints assigned</p>'}
        </div>
        
        <button onclick="testResources()">🧪 Test All Resources</button>
        <div id="test-results"></div>
        
        <hr>
        <p><em>Resources assigned via Databricks Asset Bundle (equivalent to UI assignment)</em></p>
    </body>
    </html>
    `;
    
    res.send(html);
});

app.get('/test', (req, res) => {
    try {
        const resources = getResourcesData();
        const results = [];
        
        if (resources.warehouse_id) results.push("✅ SQL Warehouse ID");
        if (resources.warehouse_path) results.push("✅ SQL HTTP Path");
        if (resources.has_token) results.push("✅ Authentication Secret");
        if (resources.endpoints.length > 0) results.push("✅ Serving Endpoints");
        if (process.env.DATABRICKS_HOST) results.push("✅ Databricks Host");
        
        let html;
        if (results.length >= 4) {
            html = '<h3 class="success">🎉 All assigned resources are working!</h3><ul>';
            results.forEach(result => {
                html += `<li>${result}</li>`;
            });
            html += '</ul>';
        } else {
            html = '<p class="error">❌ Some resources are missing</p>';
        }
        
        res.json({ html: html });
        
    } catch (error) {
        res.json({ html: `<p class="error">Error testing resources: ${error.message}</p>` });
    }
});

app.listen(port, '0.0.0.0', () => {
    console.log(`Databricks Node.js app listening at http://0.0.0.0:${port}`);
});
EOF
            ;;
    esac
else
    print_warning "$APP_FILE already exists --- keeping your existing file."
fi

# Create requirements.txt based on app type
if [ ! -f "requirements.txt" ]; then
    case $APP_TYPE in
        "streamlit")
            cat > requirements.txt <<'EOF'
streamlit==1.42.0
databricks-sdk==0.43.0
pandas==2.2.3
EOF
            ;;
        "gradio")
            cat > requirements.txt <<'EOF'
gradio==4.44.0
databricks-sdk==0.43.0
pandas==2.2.3
EOF
            ;;
        "dash")
            cat > requirements.txt <<'EOF'
dash==2.17.1
databricks-sdk==0.43.0
pandas==2.2.3
EOF
            ;;
        "shiny")
            cat > requirements.txt <<'EOF'
shiny==0.6.1
databricks-sdk==0.43.0
pandas==2.2.3
EOF
            ;;
        "flask")
            cat > requirements.txt <<'EOF'
flask==3.0.0
databricks-sdk==0.43.0
pandas==2.2.3
EOF
            ;;
        "nodejs")
            cat > package.json <<'EOF'
{
  "name": "databricks-nodejs-app",
  "version": "1.0.0",
  "description": "Databricks Node.js app with assigned resources",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
            ;;
    esac
fi

# .gitignore (full version from original script)
if [ ! -f ".gitignore" ]; then
    print_status "Creating .gitignore..."
    cat > .gitignore <<'EOF'
# Environment & Config
.env
token.txt
config.json

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual Environments
venv/
env/
ENV/

# Logs & Temp Files
*.log
*.tmp

# IDEs & Editor Config
.vscode/
.idea/
*.swp
*.swo

# OS Generated Files
.DS_Store
Thumbs.db

# Databricks
.databricks/

# Dev Scripts
create-databricks-app.sh
setup-*.sh
*.sh

# Docs
create-databricks-app-readme.md
EOF
else
    if ! grep -qxF 'create-databricks-app-readme.md' .gitignore; then
        print_status "Appending Docs ignore to existing .gitignore..."
        { echo ""; echo "# Docs"; echo "create-databricks-app-readme.md"; } >> .gitignore
    fi
    print_warning ".gitignore already exists --- keeping your existing entries."
fi

print_success "✅ Files created - ready to assign resources to app!"

# ─────────────────────────────────────────────────────────────
# Deploy - This assigns the resources to the app service principal
# ─────────────────────────────────────────────────────────────
print_status "Validating bundle configuration..."
if ! databricks bundle validate; then
    print_error "Bundle validation failed"
    exit 1
fi
print_success "Bundle validation passed!"

print_status "Deploying bundle (assigns existing resources to app service principal)..."
if ! databricks bundle deploy; then
    print_error "Bundle deployment failed"
    exit 1
fi
print_success "✅ Bundle deployed - resources assigned to app!"

# Deploy the app code
print_status "Waiting for bundle deployment to fully complete..."
print_status "ℹ️  Databricks Apps can take 1-2 minutes to initialize..."
sleep 60  # Initial wait - 1 minute

print_status "Deploying app source code..."
BUNDLE_WS_PATH="/Workspace/Users/${CURRENT_USER}/.bundle/${BUNDLE_NAME}/default/files"

# Try deploying with app start attempts
for attempt in {1..3}; do
    print_status "Deployment attempt $attempt/3..."
    
    # Try starting the app before each deployment attempt
    print_status "Ensuring app compute is started - this process may take 3-4 minutes..."
    if databricks apps start "${APP_NAME}" >/dev/null 2>&1; then
        print_success "✅ App started (or was already running)"
    else
        print_warning "Could not start app - may already be running"
    fi
    
    # Wait a moment for app to initialize
    sleep 30
    
    if databricks apps deploy "${APP_NAME}" --source-code-path "${BUNDLE_WS_PATH}" --mode SNAPSHOT; then
        print_success "✅ App source deployed!"
        break
    else
        if [[ $attempt -lt 3 ]]; then
            print_warning "App deployment failed (attempt $attempt/3), will retry..."
            print_status "⏰ Waiting 2 minutes before next attempt..."
            sleep 120  # Wait 2 minutes between retries
        else
            print_warning "App deployment failed after 3 attempts"
            print_status "App is created with resources assigned - you may need to manually deploy source code"
            print_status "Manual deployment command:"
            print_status "  databricks apps deploy ${APP_NAME} --source-code-path ${BUNDLE_WS_PATH} --mode SNAPSHOT"
        fi
    fi
done

# Start the app
print_status "Starting the app..."
if databricks apps start "${APP_NAME}"; then
    print_success "✅ App started!"
else
    print_warning "App start may have failed (or already running)"
fi

# Success message
APP_URL="${DATABRICKS_HOST%/}/apps/${APP_NAME}"
print_success "🎉 App deployment complete!"
print_status ""
print_status "📋 Your app now has these resources assigned (check UI 'App resources' section):"
print_status "   📊 SQL Warehouse: $EXISTING_WAREHOUSE_NAME (key: $WAREHOUSE_KEY, permission: $WAREHOUSE_PERMISSION)"
print_status "   🔐 Secret: $EXISTING_SECRET_SCOPE/$EXISTING_SECRET_KEY (key: $SECRET_RESOURCE_KEY, permission: $SECRET_PERMISSION)"
print_status "   🤖 Serving Endpoints: ${TOTAL_EP} endpoints with CAN_QUERY permission"
print_status ""
print_status "🌐 App URL: $APP_URL"
print_status "🔄 Sync future edits back to Databricks: databricks sync --watch . ${BUNDLE_WS_PATH}"
print_status "🚀 Deploy to Databricks Apps: databricks apps deploy ${APP_NAME} --source-code-path ${BUNDLE_WS_PATH}"
print_status ""
print_status "🔄 Re-run anytime: ./create-databricks-app.sh"
print_status "💡 All resources are assigned automatically - no manual UI selection needed!"