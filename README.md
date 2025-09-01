# End-to-End Databricks Apps Automation Script

**Automate the end-to-end creation through deployment and testing of Databricks Apps in 6 minutes or less with existing resource assignment - No more manual UI clicking!**

## Why Databricks Apps Matter
Databricks Apps are one of Databricks’ newest and most powerful yet underutilized features—a true hidden gem in the Databricks platform. 

Databricks Apps let you transform your data into production-ready, interactive web applications that run directly within your Databricks environment, providing complete security and governance. They provide a bridge between your data and meaningful, useful data apps for business users, including Gen AI applications, interactive data apps, and predictive analytics.

After building / vibe-coding over 40 custom Databricks Apps across various projects, a pattern became clear around app number 30: **I was spending significant time on repetitive setup tasks before I could focus on the actual application logic.** Each app required the same manual resource assignment process, which involved clicking through UI dropdowns, selecting SQL warehouses, assigning serving endpoints, configuring secrets, setting permissions, and starting compute, among other tasks. This repetitive workflow was consuming valuable time, time that could be better spent focusing on building useful functions within the data applications themselves.

The automation script you'll find here was born from this realization. It eliminates the manual setup phase entirely, allowing you to jump straight to what matters: building your custom Databricks data application or adding it to the project immediately. The **script supports all six Databricks Data App types** (I like this optionality that Databricks gives you) and automatic resource discovery and assignment. **You can go from naming your application to a deployed and tested working application in 5-6 minutes total**.

## Problem Solved

Creating Databricks Apps in the UI is a multi-step process that involves:
- Creating the app and configuring its name/settings
- Selecting from 6 different data app types (Streamlit, Gradio, Dash, Shiny, Flask, Node.js)
- Manually selecting existing resources (SQL warehouses, secrets, serving endpoints) from dropdowns
- Assigning proper permissions and resource keys for each resource
- Starting the compute environment
- Deploying your application code
- Testing that all resources are properly connected

This script automates the **entire end-to-end workflow** - from app creation to a working, tested application. It's truly a one-command solution that takes you from zero to a fully functional Databricks app with all resources configured and a working, sample data application ready to customize.

## What This Script Does

**Complete End-to-End Databricks App Creation:**
- **Creates the app** with proper naming and configuration
- **Supports all 6 Databricks App types**: Streamlit (default), Gradio, Dash, Shiny, Flask, Node.js
- **Automatically discovers** your existing Databricks resources
- **Assigns resources** to the app (equivalent to UI dropdown selection + permissions + resource keys)
- **Starts compute environment** for the application
- **Deploys and starts** the complete application
- **Provides a sample app** that tests all resource connections
- **Outputs app URL and commands** for future sync and deployment
- **Validates everything works** with built-in resource testing

**Your Next Step:** Simply replace the generated app file with your custom application code, then sync and deploy using the commands provided by the script.

## Architecture

The script uses **Databricks Asset Bundles** to:
1. Reference your existing resources (doesn't create new ones)
2. Assign them to the app's service principal with proper permissions
3. Make resources available via environment variables in your app

### Resource Assignment Flow
```
Your Existing Resources → Bundle References → App Service Principal → Environment Variables
```

## Prerequisites

### Required Files
You only need these two files to get started:
- **`.env`** - Your Databricks credentials and configuration
- **`create-databricks-app.sh`** - The automation script

All other files (databricks.yml, app.yaml, app.py/app.js, requirements.txt/package.json, .gitignore) are created automatically by the script.

### Required Tools
- **Databricks CLI** v0.261.0+ (`databricks --version`)
- **jq** for JSON parsing (`jq --version`)
- **bash** (works on macOS, Linux, WSL)

### Required Environment
Create a `.env` file in your project directory:

```bash
# --- Databricks auth (required) ---
# Your Databricks workspace URL - find this in your workspace URL bar
DATABRICKS_HOST=your-databricks-host-here

# Personal access token - generate from User Settings > Developer > Access tokens
DATABRICKS_TOKEN=your-databricks-token-here

# SQL warehouse ODBC path (kept same across apps) - get from SQL warehouse connection details
SQL_HTTP_PATH=/sql/1.0/warehouses/your-warehouse-id-here

# Secret scope & key used by the app (stored in workspace)
SECRET_SCOPE=your-secret-scope-name
SECRET_KEY=secret
APP_SECRET_NAME=your-databricks-token-secret-name

# --- Defaults for interactive prompts (optional) ---
# Unity Catalog defaults - customize for your environment
DEFAULT_UC_CATALOG=your-catalog-name
DEFAULT_UC_SCHEMA=your-schema-name
DEFAULT_UC_TABLE=your-table-name

```

## Before You Run: Fill in `.env` (what to update)

These are loaded by the script at startup; some are required. The script will exit if `DATABRICKS_HOST` or `DATABRICKS_TOKEN` are missing. :contentReference[oaicite:1]{index=1}

### ✅ Required
- **DATABRICKS_HOST** – your workspace URL (e.g., `https://adb-xxxx.azuredatabricks.net`)
- **DATABRICKS_TOKEN** – PAT from **User Settings → Developer → Access tokens**
- **SQL_HTTP_PATH** – copy from your SQL Warehouse connection details; if omitted, the app falls back to `"/sql/1.0/warehouses/${WAREHOUSE_ID}"` discovered at deploy time. :contentReference[oaicite:2]{index=2}
- **SECRET_SCOPE** and **APP_SECRET_NAME** – should match the scope/key you configure in the script (see next section). The app reads the token via the assigned secret resource at runtime. :contentReference[oaicite:3]{index=3}

### Optional: Defaults for interactive prompts
- **DEFAULT_UC_CATALOG**, **DEFAULT_UC_SCHEMA**, **DEFAULT_UC_TABLE** – seeds for the prompts (you can override at runtime); align these with the script’s defaults to avoid surprises. :contentReference[oaicite:4]{index=4}

> `.env` is already ignored by `.gitignore`, so you won’t commit credentials. :contentReference[oaicite:5]{index=5}


### Existing Databricks Resources
The script expects these resources to already exist in your Databricks workspace:

#### Default Resource Configuration (this is my standard resource config)
- **SQL Warehouse**: Your existing SQL warehouse name
- **Secret Scope**: Your secret scope with databricks token
- **8 Foundation Model Serving Endpoints** (customizable in script):
  1. `databricks-claude-sonnet-4`
  2. `databricks-claude-opus-4` 
  3. `databricks-claude-3-7-sonnet`
  4. `databricks-meta-llama-3-1-8b-instruct`
  5. `databricks-meta-llama-3-3-70b-instruct`
  6. `databricks-gemma-3-12b`
  7. `databricks-llama-4-maverick`
  8. `databricks-gpt-oss-120b`

#### Unity Catalog Defaults
- **Catalog**: Your Unity Catalog name
- **Schema**: Your schema name
- **Table**: Your table name

## Before You Run: Update These in `create-databricks-app.sh`

This script **assigns your existing resources** to the app via the bundle; it does not create them. Make sure the names here match resources that already exist in your workspace. :contentReference[oaicite:7]{index=7}

### 1) SQL Warehouse (required)

```bash
EXISTING_WAREHOUSE_NAME="your-databricks-warehouse-name"
# Permission used when assigning to the app:
WAREHOUSE_PERMISSION="CAN_USE"
```

### 2) Secret scope and key (required)

```bash
EXISTING_SECRET_SCOPE="your-secret-scope-name"
EXISTING_SECRET_KEY="your-databricks-token-secret"
# Permission used when assigning to the app:
SECRET_PERMISSION="READ"
```
The app reads `DATABRICKS_TOKEN` via this assigned secret (no plaintext token in files).

### 3) Foundation model Serving Endpoints (customize to your workspace)

```bash
ENDPOINT_NAMES[1]="databricks-claude-sonnet-4"
# ...
ENDPOINT_NAMES[8]="databricks-gpt-oss-120b"
```
These are assigned to the app in the bundle with the specified permission.

### 4) Unity Catalog prompt defaults (optional)

```bash
DEFAULT_UC_CATALOG="your-catalog-name"
DEFAULT_UC_SCHEMA="your-schema-name"
DEFAULT_UC_TABLE="your-table-name"
```
These flow into the generated app.yaml env for your app.

### 5) SQL Warehouse HTTP path behavior (FYI)

`app.yaml` sets `DATABRICKS_SQL_HTTP_PATH` to your `.env` value if present, otherwise it falls back to `"/sql/1.0/warehouses/${WAREHOUSE_ID}"` derived from the discovered warehouse.

## Usage

### Quick Start
```bash
# 1. Make script executable (required first time)
chmod +x create-databricks-app.sh

# 2. Run the automation
./create-databricks-app.sh
```

### Interactive Prompts
The script will prompt you for:
```
Select Databricks Data App Type:
1. Streamlit (default)
2. Gradio
3. Dash
4. Shiny
5. Flask
6. Node.js
Enter choice 1-6 (default 1):

App name (lowercase, a-z0-9-, between 2-30 characters) (auto-detected): my-app
Bundle name (lowercase, a-z0-9-) (my-app-bundle): 
Unity Catalog (UC_CATALOG) (your-catalog-name): 
UC schema (UC_SCHEMA) (your-schema-name): 
UC table (UC_TABLE) (your-table-name): 
Add extra Serving Endpoints? Enter count 0-4 (default 0): 0
```

### Command Line Usage
```bash
# Specify app name directly
./create-databricks-app.sh my-awesome-app

# Skip all prompts using defaults (Streamlit app)
echo -e "1\n\n\n\n\n\n0" | ./create-databricks-app.sh my-app
```

### App Type Selection
Choose from 6 supported Databricks Data App types:

1. **Streamlit** - Interactive data apps with widgets (default)
2. **Gradio** - Machine learning model interfaces and demos  
3. **Dash** - Interactive web applications with plotly integration
4. **Shiny** - R-style reactive web applications for Python
5. **Flask** - Lightweight web framework for custom applications
6. **Node.js** - JavaScript/Express server applications

Each app type creates appropriate:
- **Dependencies**: `requirements.txt` for Python frameworks, `package.json` for Node.js
- **Runtime command**: Correct startup command in `app.yaml`
- **Sample application**: Working demo that shows assigned resources

### Adding Extra Serving Endpoints
The script supports adding 0-4 additional serving endpoints beyond the 8 default Foundation Model endpoints:

```
Add extra Serving Endpoints? Enter count 0-4 (default 0): 2
Extra endpoint 9 name (must match existing serving endpoint in Databricks) (your-existing-endpoint-name): my-custom-model
Extra endpoint 10 name (must match existing serving endpoint in Databricks) (your-existing-endpoint-name): another-model
```

**Requirements for extra endpoints:**
- The serving endpoint must already exist in your Databricks workspace
- You must provide the exact endpoint name when prompted
- The script will verify the endpoint exists before deployment

**What gets created automatically:**
- Resource key: `serving-endpoint-9`, `serving-endpoint-10`, etc.
- Environment variables: `DBX_ENDPOINT_9`, `DBX_ENDPOINT_10`, etc.  
- URL environment variables: `DATABRICKS_ENDPOINT_9_URL`, `DATABRICKS_ENDPOINT_10_URL`, etc.
- Permission: `CAN_QUERY` for all additional endpoints

## Customizing Default Endpoints

### Modifying Serving Endpoints
To change the order, names, or add/remove default serving endpoints, edit the script:

```bash
# Find this section in create-databricks-app.sh:
# Your 8 default serving endpoints - using arrays instead of associative arrays
declare -a ENDPOINT_KEYS ENDPOINT_NAMES ENDPOINT_PERMISSIONS
ENDPOINT_KEYS[1]="serving-endpoint"
ENDPOINT_NAMES[1]="databricks-claude-sonnet-4"
ENDPOINT_PERMISSIONS[1]="CAN_QUERY"

ENDPOINT_KEYS[2]="serving-endpoint-2"
ENDPOINT_NAMES[2]="databricks-claude-opus-4"
ENDPOINT_PERMISSIONS[2]="CAN_QUERY"

# ... continue for endpoints 3-8
```

**To customize:**
- **Change order**: Swap array positions (e.g., swap positions 1 and 2)
- **Change names**: Update `ENDPOINT_NAMES[X]` to match your serving endpoints
- **Add/remove**: Add or remove array entries (keep `ENDPOINT_KEYS[X]` as is)
- **Change permissions**: Update `ENDPOINT_PERMISSIONS[X]` (typically "CAN_QUERY")

### Modifying Other Resources
Edit these variables in the script to match your environment:

```bash
# SQL Warehouse (from your existing setup)
EXISTING_WAREHOUSE_NAME="your-sql-warehouse-name"

# Secret (from your existing secret scope)  
EXISTING_SECRET_SCOPE="your-secret-scope"
EXISTING_SECRET_KEY="your-secret-key-name"

# Unity Catalog defaults
DEFAULT_UC_CATALOG="your-catalog-name"
DEFAULT_UC_SCHEMA="your-schema-name" 
DEFAULT_UC_TABLE="your-table-name"
```

## Generated Files

The script creates a complete Databricks app structure:

```
your-project/
├── create-databricks-app.sh     # The automation script (you provide)
├── .env                         # Your credentials (you provide)
├── databricks.yml              # Bundle configuration (generated)
├── app.yaml                    # App runtime configuration (generated)  
├── app.py or app.js            # Sample app (generated, depends on app type)
├── requirements.txt            # Python dependencies (generated for Python apps)
├── package.json               # Node.js dependencies (generated for Node.js apps)
├── .gitignore                  # Git ignore rules (generated)
└── .databricks/               # Bundle cache (generated)
```

### Dependencies by App Type
- **Python frameworks** (Streamlit, Gradio, Dash, Shiny, Flask): Creates `requirements.txt`
- **Node.js**: Creates `package.json` instead of `requirements.txt`

## Script Output

When the script completes successfully, it provides:

### App URL
```bash
🌐 App URL: https://your-workspace.databricks.net/apps/your-app
```

### Development Commands
```bash
🔄 Sync future edits back to Databricks: databricks sync --watch . /Workspace/Users/your-email/.bundle/your-app-bundle/default/files

🚀 Deploy to Databricks Apps: databricks apps deploy your-app --source-code-path /Workspace/Users/your-email/.bundle/your-app-bundle/default/files
```

These commands are specific to your app and can be used for ongoing development.

## Expected Results

### In Databricks UI
After running the script, your new app will show in the **"App resources"** section:

| Key | Type | Details | Permissions |
|-----|------|---------|-------------|
| sql-warehouse | SQL Warehouse | your-sql-warehouse-name | Can use |
| secret | Secret | Key: your-secret-key-name | Can read |
| serving-endpoint | Serving endpoint | databricks-claude-sonnet-4 | Can query |
| serving-endpoint-2 | Serving endpoint | databricks-claude-opus-4 | Can query |
| ... | ... | ... | ... |

### In Your App
The generated sample app demonstrates resource access:
```python
import os

# Access assigned resources (Python example)
warehouse_id = os.getenv('DATABRICKS_SQL_WAREHOUSE_ID')  # From sql-warehouse resource
warehouse_path = os.getenv('DATABRICKS_SQL_HTTP_PATH')   # HTTP path for connections
token = os.getenv('DATABRICKS_TOKEN')                   # From secret resource  
main_endpoint = os.getenv('DBX_ENDPOINT')               # Main serving endpoint
endpoint_2 = os.getenv('DBX_ENDPOINT_2')                # Additional endpoints

# Unity Catalog configuration
catalog = os.getenv('UC_CATALOG')
schema = os.getenv('UC_SCHEMA')
table = os.getenv('UC_TABLE')
```

### Sample App Features
Each generated app includes:
- **Resource Status Dashboard**: Shows all assigned resources and their status
- **Resource Testing**: Button to test connectivity to all assigned resources
- **Environment Variable Display**: Shows how resources are accessed via env vars
- **Framework-specific UI**: Streamlit widgets, Gradio interfaces, Dash components, etc.

## Development Workflow

### Initial Setup
```bash
# Make script executable and run
chmod +x create-databricks-app.sh
./create-databricks-app.sh my-project
```

### Ongoing Development  
```bash
# Test your app locally during development
streamlit run app.py  # For Streamlit apps
python app.py         # For other Python frameworks
node app.js           # For Node.js apps

# Edit your app file with real application code
vim app.py  # or app.js for Node.js

# Sync changes during development (use the exact command from script output)
databricks sync --watch . /Workspace/Users/your-email/.bundle/your-bundle/default/files

# Or deploy specific updates (use the exact command from script output)
databricks apps deploy your-app --source-code-path /path/to/source --mode SNAPSHOT
```

### Re-running the Script
```bash
# Complete recreation of the app
./create-databricks-app.sh
```

## Troubleshooting

### Common Issues

#### App Name Validation
**Error**: "App name must be between 2-30 characters"
**Solution**: App names must be 2-30 characters, lowercase, using only a-z, 0-9, and hyphens.

#### "Cannot find warehouse" Error
**Solution**: Update `EXISTING_WAREHOUSE_NAME` in the script to match your warehouse name.
```bash
databricks warehouses list --output json | jq -r '.[].name'  # List your warehouses
```

#### "Secret scope not found" Error
**Solution**: Create the secret scope or update `EXISTING_SECRET_SCOPE` in the script.
```bash
databricks secrets list-scopes --output json | jq -r '.[].name'  # List your scopes
```

#### "Serving endpoint not found" warnings
**Solution**: These are warnings, not errors. Some Foundation Model endpoints may not be available in your region. The script will continue with available endpoints.

### Debug Commands
```bash
# Check bundle validation
databricks bundle validate

# Check app status
databricks apps get your-app-name

# View app logs
databricks apps logs your-app-name

# Manual app start
databricks apps start your-app-name
```

## Security Notes

### Permissions
The script assigns minimal required permissions:
- **SQL Warehouse**: `CAN_USE` (query access only)
- **Secret**: `READ` (read access only)  
- **Serving Endpoints**: `CAN_QUERY` (inference access only)

### Token Storage
- Your `DATABRICKS_TOKEN` is stored in `.env` (automatically added to `.gitignore`)
- Tokens are accessed by the app via assigned secret resource
- No tokens are hardcoded in bundle files

## Key Features

### Automatic Resource Discovery
- Uses Databricks CLI to verify resource existence
- Provides helpful warnings for missing resources
- Continues deployment with available resources

### Multi-Framework Support
- 6 different app types with appropriate configurations
- Framework-specific dependencies and runtime commands
- Working sample apps for each framework type

### Robust Deployment Process
1. **Validation Phase**: Validates bundle configuration
2. **Deployment Phase**: Deploys bundle to assign resources
3. **Code Deployment**: Deploys app source code with retry logic
4. **Startup Phase**: Starts the app automatically

### Smart Output
- Provides exact app URL for immediate access
- Outputs app-specific sync and deploy commands
- Color-coded logging with clear success indicators

## 📈 Success Indicators

When the script completes successfully, you should see:
```
✅ Bundle deployed - resources assigned to app!
✅ App source deployed!
✅ App started!
🎉 App deployment complete!

📋 Your app now has these resources assigned:
   📊 SQL Warehouse: your-sql-warehouse-name
   🔐 Secret: your-secret-scope/your-secret-key  
   🤖 Serving Endpoints: 8 endpoints with CAN_QUERY permission

🌐 App URL: https://your-workspace.databricks.net/apps/your-app
🔄 Sync future edits back to Databricks: databricks sync --watch . /path/to/files
🚀 Deploy to Databricks Apps: databricks apps deploy your-app --source-code-path /path/to/files
```

---

**Ready to automate your Databricks app creation and deployment!** No more manual resource clicking - just run the script and add your custom app code.