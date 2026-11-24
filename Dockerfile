
FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Copy dependencies
COPY app/requirements.txt .

# Install dependencies and create a non-root user
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home appuser

# Copy application code
COPY app/ .

# Run as non-root user
USER appuser

# Application port
EXPOSE 3000

# Start Flask application
CMD ["python", "app.py"]
