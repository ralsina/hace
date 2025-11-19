# Environment Variables

Hacé provides flexible environment variable management for your build processes.

## Setting Environment Variables

### In Hacefile.yml

```yaml
env:
  # Set environment variables
  NODE_ENV: "production"
  PATH: "/usr/local/bin:$PATH"
  DEBUG: "true"

  # Set empty string
  EMPTY_VAR: ""

  # Unset environment variables
  UNWANTED_VAR: null
```

### Precedence

Environment variables are resolved in this order:

1. **Hacefile.yml `env` section** (highest priority)
2. **Command line exports** (e.g., `VAR=value hace build`)
3. **System environment** (existing shell environment)

### Inheritance and Modification

```yaml
env:
  # Modify existing PATH
  PATH: "/opt/myapp/bin:$PATH"

  # Set new variables
  APP_HOME: "/opt/myapp"
  LOG_LEVEL: "info"

  # Override system variables
  HOME: "/custom/home"  # Not recommended!
```

## Using Environment Variables

### In Commands

```yaml
tasks:
  build:
    commands: |
      echo "Building with NODE_ENV=$NODE_ENV"
      echo "PATH is $PATH"
      crystal build src/main.cr

  deploy:
    commands: |
      # Environment variables are available to all commands
      aws s3 cp dist/ s3://$BUCKET_NAME/ --recursive
```

### Conditional Logic with Environment

```yaml
tasks:
  deploy:
    commands: |
      {% if '$NODE_ENV' == 'production' %}
      echo "Deploying to production"
      kubectl apply -f k8s/production/
      {% elif '$NODE_ENV' == 'staging' %}
      echo "Deploying to staging"
      kubectl apply -f k8s/staging/
      {% else %}
      echo "Unknown environment: $NODE_ENV"
      {% endif %}
```

## Environment Variable Scenarios

### Database Configuration

```yaml
env:
  DATABASE_URL: "postgresql://localhost:5432/myapp_dev"
  REDIS_URL: "redis://localhost:6379"

tasks:
  migrate:
    commands: |
      echo "Running migrations on $DATABASE_URL"
      crystal src/migrate.cr

  seed:
    commands: |
      echo "Seeding database: $DATABASE_URL"
      crystal src/seed.cr
```

### Multi-Environment Builds

```yaml
# Development Hacefile
env:
  NODE_ENV: "development"
  API_URL: "http://localhost:3000"
  DEBUG: "true"

tasks:
  build:
    commands: |
      echo "Building for $NODE_ENV"
      npm run build:dev

# Production Hacefile (production.yml)
env:
  NODE_ENV: "production"
  API_URL: "https://api.myapp.com"
  DEBUG: "null"

tasks:
  build:
    commands: |
      echo "Building for $NODE_ENV"
      npm run build:prod
```

### Temporary Environment Overrides

```bash
# Override environment for single command
NODE_ENV=staging hace deploy

# Multiple environment variables
NODE_ENV=production DEBUG=false API_URL=https://api.prod.com hace build
```

## Environment Variable Security

### Handling Secrets

```yaml
# Good: Get secrets from environment
env:
  API_KEY: null  # Unset any existing value

tasks:
  deploy:
    commands: |
      # Expect API_KEY from external source
      if [ -z "$API_KEY" ]; then
        echo "Error: API_KEY not set"
        exit 1
      fi
      curl -H "Authorization: Bearer $API_KEY" https://api.example.com/deploy
```

```yaml
# Bad: Hardcoding secrets (DON'T DO THIS)
env:
  API_KEY: "sk-1234567890abcdef"  # SECURITY RISK!
```

### Environment Files with Dotenv Support

Hacé has built-in support for loading environment variables from `.env` files.
When a Hacefile.yml is processed, Hacé automatically looks for a `.env` file
in the current working directory and loads its variables into the environment.

#### Automatic .env Loading

```bash
# .env file (not committed to version control)
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=sk-development-key
DEBUG=true
APP_NAME=MyApp
VERSION=1.0.0
```

```yaml
# Hacefile.yml
tasks:
  build:
    commands: |
      echo "Building $APP_NAME version $VERSION"
      echo "Database: $DATABASE_URL"
      echo "Debug mode: $DEBUG"
      crystal build src/main.cr -o bin/$APP_NAME

  deploy:
    commands: |
      echo "Deploying $APP_NAME with API key"
      curl -H "Authorization: Bearer $API_KEY" https://api.example.com/deploy
```

#### How It Works

1. **Automatic Loading**: Hacé loads `.env` files from the current directory
2. **Shell Expansion**: Variables available using `${VAR_NAME}` shell syntax
3. **Graceful Handling**: If no `.env` file exists, Hacé continues normally
4. **Logging**: When a `.env` file is loaded, Hacé logs the file that was loaded

#### Environment File Format

```bash
# .env file syntax
KEY=value                    # Simple assignment
APP_NAME="MyApp"             # Values with spaces
DATABASE_URL=postgres://...  # Complex values
DEBUG=true                   # Booleans
VERSION=1.2.3                # Numbers

# Comments are supported
# Lines starting with # are ignored
```

#### Variable Precedence

Environment variables are resolved in this order (highest to lowest priority):

1. **Hacefile.yml `env` section** (highest priority)
2. **Command line exports** (e.g., `VAR=value hace build`)
3. **.env file variables**
4. **System environment** (existing shell environment)

#### Examples

##### Development Environment Setup

```bash
# .env
NODE_ENV=development
API_URL=http://localhost:3000
DEBUG=true
DATABASE_URL=postgresql://localhost:5432/myapp_dev
```

```yaml
# Hacefile.yml
tasks:
  serve:
    commands: |
      echo "Starting server in $NODE_ENV mode"
      echo "API URL: $API_URL"
      echo "Debug: $DEBUG"
      npm start

  migrate:
    commands: |
      echo "Running migrations on $DATABASE_URL"
      npm run migrate
```

##### Production Deployment

```bash
# .env.production (for production)
NODE_ENV=production
API_URL=https://api.myapp.com
DEBUG=false
DATABASE_URL=postgresql://prod-server:5432/myapp_prod
```

```bash
# Run with production environment
cp .env.production .env
hace deploy
```

##### Multi-Environment Configuration

```yaml
# Hacefile.yml
variables:
  app_name: "MyAwesomeApp"

tasks:
  show-env:
    commands: |
      echo "App: $APP_NAME"  # From .env or system env
      echo "Name: {{ app_name }}"  # From Hacefile variables
      echo "Environment: $NODE_ENV"
      echo "Database: $DATABASE_URL"

  build-dev:
    commands: |
      echo "Building development version"
      crystal build src/main.cr -o bin/{{ app_name }}-dev

  build-prod:
    commands: |
      echo "Building production version"
      crystal build --release src/main.cr -o bin/{{ app_name }}
```

#### Best Practices

1. **Don't commit sensitive .env files**: Add `.env` to `.gitignore`
2. **Use descriptive variable names**: `DATABASE_URL` instead of `DB`
3. **Provide environment-specific files**: `.env.development`, `.env.production`
4. **Document required variables**: List environment dependencies in README
5. **Use null to unset**: Explicitly unset unwanted variables in Hacefile.yml

```bash
# .gitignore
.env
.env.local
.env.*.local
```

```yaml
# Hacefile.yml - clear sensitive defaults
env:
  # Clear any existing secrets to ensure they come from .env
  API_KEY: null
  DATABASE_PASSWORD: null
  SECRET_KEY: null

tasks:
  validate-secrets:
    commands: |
      if [ -z "$API_KEY" ]; then
        echo "Error: API_KEY must be set in .env file"
        exit 1
      fi
      echo "All required secrets are set"
```

## Advanced Environment Patterns

### Environment-Specific Configurations

```yaml
variables:
  env_file: "{{ '$NODE_ENV' | default('development') }}.env"

tasks:
  setup:
    commands: |
      echo "Loading environment from {{ env_file }}"
      if [ -f "{{ env_file }}" ]; then
        export $(cat {{ env_file }} | xargs)
        echo "Environment loaded from {{ env_file }}"
      else
        echo "No {{ env_file }} file found"
      fi

  build:
    dependencies:
      - setup
    commands: |
      crystal build src/main.cr -o bin/app
```

### Dynamic Environment Variables

```yaml
tasks:
  setup:
    commands: |
      # Set dynamic environment variables
      export BUILD_DATE=$(date +%Y-%m-%d)
      export COMMIT_HASH=$(git rev-parse --short HEAD)
      export BUILD_NUMBER=$BUILD_NUMBER

  build:
    dependencies:
      - setup
    commands: |
      echo "Build date: $BUILD_DATE"
      echo "Commit: $COMMIT_HASH"
      echo "Build number: $BUILD_NUMBER"
      crystal build src/main.cr -o bin/app
```

### Environment Validation

```yaml
tasks:
  validate-env:
    commands: |
      # Required environment variables
      required_vars=("DATABASE_URL" "API_KEY" "REDIS_URL")

      for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
          echo "Error: Required environment variable $var is not set"
          exit 1
        fi
        echo "✓ $var is set"
      done

  migrate:
    dependencies:
      - validate-env
    commands: |
      crystal src/migrate.cr
```

## Environment Variables in Template Files

### Jinja Template Integration

```yaml
variables:
  app_name: "myapp"

tasks:
  config:
    commands: |
      # Generate config file with environment variables
      cat > config.yml << EOF
      app_name: {{ app_name }}
      environment: $NODE_ENV
      database_url: $DATABASE_URL
      api_key: {% if '$API_KEY' %}***REDACTED***{% else %}null{% endif %}
      EOF

  show-config:
    dependencies:
      - config
    commands: |
      cat config.yml
```

## Environment Variable Best Practices

1. **Don't commit secrets**: Keep sensitive data out of Hacefile.yml
2. **Use null to unset**: Explicitly unset unwanted variables
3. **Document required variables**: List environment dependencies in documentation
4. **Provide defaults**: Use reasonable defaults for development
5. **Validate early**: Check required variables before complex tasks

```yaml
# Example of good practice
env:
  # Development defaults
  NODE_ENV: "development"
  LOG_LEVEL: "debug"

  # Clear production secrets
  API_KEY: null
  DATABASE_URL: null

tasks:
  check-env:
    commands: |
      if [ "$NODE_ENV" = "production" ] && [ -z "$API_KEY" ]; then
        echo "Error: API_KEY required for production"
        exit 1
      fi
```
