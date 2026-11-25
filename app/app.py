
from flask import Flask, jsonify

# Create Flask application
app = Flask(__name__)


# Home endpoint
@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "application": "CI/CD Web Application",
        "message": "Welcome to my home page!",
        "status": "running"
    }), 200


# Health check endpoint
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "healthy",
        "message": "Application is working properly"
    }), 200


# Start application
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
