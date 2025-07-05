#!/bin/bash

# Ensure we receive the commit hash or build number as an argument (or use default)
BUILD_ID=${1:-"unknown-build-id"}  # Default to "unknown-build-id" if not passed
COMMIT_HASH=${2:-"unknown-commit-hash"}  # Default to "unknown-commit-hash" if not passed

# Variables (these are still container-specific names)
CONTAINER_NAME="cookingchallenge"
TEMP_CONTAINER_NAME="cookingchallenge-old"
NEW_IMAGE="cookingchalleng:latest"
NGINX_CONF="/etc/nginx/sites-available/default"
HEALTHCHECK_URL="http://localhost/health"
WAIT_TIME=60  # seconds to wait for health to become 'healthy'
EMAIL_RECIPIENT="your-email@example.com"
SMTP_SERVER="smtp.example.com"  # For example, use your SMTP server settings
SMTP_PORT="587"  # Adjust accordingly
SMTP_USER="smtp-user@example.com"
SMTP_PASS="smtp-password"

# Function to send email notifications
send_email() {
  local subject=$1
  local body=$2
  echo -e "Subject:$subject\n\n$body" | sendmail -S $SMTP_SERVER -p $SMTP_PORT -au$SMTP_USER -ap$SMTP_PASS $EMAIL_RECIPIENT
}

# Step 1: Rename the old container to avoid conflicts
echo "Renaming old container $CONTAINER_NAME to $TEMP_CONTAINER_NAME... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
docker rename $CONTAINER_NAME $TEMP_CONTAINER_NAME || { echo "Error renaming old container"; exit 1; }

# Step 2: Run the new container (with the original name of the old one)
echo "Starting new container $CONTAINER_NAME... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
docker run -d --name $CONTAINER_NAME --health-cmd="curl -f $HEALTHCHECK_URL || exit 1" --health-interval=10s --health-retries=3 --health-start-period=10s $NEW_IMAGE || { echo "Error running new container"; exit 1; }

# Step 3: Get the dynamic port of the new container
NEW_CONTAINER_PORT=$(docker port $CONTAINER_NAME 80 | cut -d: -f2)
echo "New container $CONTAINER_NAME is running on port $NEW_CONTAINER_PORT."

# Step 4: Wait until the new container becomes healthy
echo "Waiting for $CONTAINER_NAME to become healthy... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
for i in $(seq 1 $WAIT_TIME); do
  status=$(docker inspect --format='{{.State.Health.Status}}' $CONTAINER_NAME)
  if [ "$status" == "healthy" ]; then
    echo "$CONTAINER_NAME is healthy! (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
    break
  fi
  echo "Waiting for healthcheck to pass... (attempt $i/$WAIT_TIME) (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
  sleep 5
done

# Step 5: Check if the new container passed healthcheck
if [ "$status" != "healthy" ]; then
  echo "Error: $CONTAINER_NAME failed to become healthy in $WAIT_TIME seconds. (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"

  # Rollback to the old container
  echo "Rolling back deployment... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"

  # Rename the new container back to a temporary name
  docker rename $CONTAINER_NAME "$CONTAINER_NAME-failed" || { echo "Error renaming new container"; exit 1; }

  # Restore the old container's name (it wasn't stopped)
  docker rename $TEMP_CONTAINER_NAME $CONTAINER_NAME || { echo "Error renaming old container back"; exit 1; }

  # Remove the failed new container
  docker rm "$CONTAINER_NAME-failed" || { echo "Error removing failed container"; exit 1; }

  # Send failure email notification
  send_email "Deployment Failed: $CONTAINER_NAME (Build: $BUILD_ID)" "Deployment of $CONTAINER_NAME (Build: $BUILD_ID, Commit: $COMMIT_HASH) failed. Rolled back to the previous version ($TEMP_CONTAINER_NAME)."

  exit 1
fi

# Step 6: Update Nginx configuration to point to the new container
echo "Updating Nginx to point to the new container... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
sed -i "s/server 127.0.0.1:[0-9]*;/server 127.0.0.1:$NEW_CONTAINER_PORT;/g" $NGINX_CONF || { echo "Error updating Nginx config"; exit 1; }

# Step 7: Reload Nginx to apply the new config
echo "Reloading Nginx to apply changes... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
nginx -s reload || { echo "Error reloading Nginx"; exit 1; }

# Step 8: Stop and remove the old container (now named $TEMP_CONTAINER_NAME)
echo "Stopping and removing old container $TEMP_CONTAINER_NAME... (Build ID: $BUILD_ID, Commit: $COMMIT_HASH)"
docker stop $TEMP_CONTAINER_NAME || { echo "Error stopping old container"; exit 1; }
docker rm $TEMP_CONTAINER_NAME || { echo "Error removing old container"; exit 1; }

# Step 9: Optionally, remove old image (if no longer needed)
# docker rmi $OLD_IMAGE

# Send success email notification
send_email "Deployment Succeeded: $CONTAINER_NAME (Build: $BUILD_ID)" "Deployment of $CONTAINER_NAME (Build: $BUILD_ID, Commit: $COMMIT_HASH) was successful and the new container is now live."

echo "Deployment completed successfully. $CONTAINER_NAME (Build: $BUILD_ID, Commit: $COMMIT_HASH) is now live!"

