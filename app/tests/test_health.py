import unittest

from app import app


class HealthTests(unittest.TestCase):

    def setUp(self):
        self.client = app.test_client()

    ##################################################

    def test_health_endpoint(self):

        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)

        data = response.get_json()

        self.assertEqual(data["status"], "healthy")

    ##################################################

    def test_metrics_endpoint(self):

        response = self.client.get("/metrics")

        self.assertEqual(response.status_code, 200)

        data = response.get_json()

        self.assertIn("application", data)
        self.assertIn("cluster", data)
        self.assertIn("database", data)

    ##################################################

    def test_readiness_endpoint(self):

        response = self.client.get("/ready")

        self.assertIn(
            response.status_code,
            [200, 503]
        )

        data = response.get_json()

        self.assertIn("status", data)


if __name__ == "__main__":
    unittest.main()
