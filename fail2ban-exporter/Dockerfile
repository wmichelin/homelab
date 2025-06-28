FROM python:3.9-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy exporter script
COPY exporter.py .

# Make script executable
RUN chmod +x exporter.py

# Expose metrics port
EXPOSE 9191

# Run exporter
CMD ["python", "exporter.py"]