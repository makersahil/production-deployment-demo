from django.shortcuts import render

# Create your views here.
from django.http import JsonResponse


def home(request):
    return JsonResponse({
        "service": "production-deployment-demo",
        "status": "running"
    })


def health(request):
    return JsonResponse({
        "status": "healthy"
    })
