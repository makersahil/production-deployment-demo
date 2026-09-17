from django.test import TestCase

# Create your tests here.
class HealthCheckTest(TestCase):
    def test_health_endpoint(self):
        response = self.client.get("/health/")
        self.assertEqual(response.status_code, 200)
