
import unittest
from app import app


class TestWebApplication(unittest.TestCase):

    def setUp(self):
        # Create a test client
        self.client = app.test_client()

    def test_home_endpoint(self):
        response = self.client.get("/")

        self.assertEqual(response.status_code, 200)

        data = response.get_json()

        self.assertEqual(
            data["status"],
            "running"
        )

    def test_health_endpoint(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)

        data = response.get_json()

        self.assertEqual(
            data["status"],
            "healthy"
        )


if __name__ == "__main__":
    unittest.main()
