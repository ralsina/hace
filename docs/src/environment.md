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

### Environment Files

Use `.env` files for local development:

```bash
# .env file (not committed to version control)
DATABASE_URL=postgresql://localhost:5432/myapp_dev
API_KEY=sk-development-key
DEBUG=true
```

```yaml
# Hacefile.yml
env:
  DATABASE_URL: null  # Will be set by .env file
  API_KEY: null

tasks:
  load-env:
    commands: |
      if [ -f .env ]; then
        export $(cat .env | xargs)
      fi

  build:
    dependencies:
      - load-env
    commands: |
      echo "Building with DATABASE_URL=$DATABASE_URL"
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

## Environment Variables in Templates

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

## Best Practices

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
