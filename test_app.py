#!/usr/bin/env python3
"""Test the app by starting it and making requests."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import create_app
from app.models import User, Brand, Quote, QuoteItem, db

app = create_app()

with app.app_context():
    brands = Brand.query.all()
    print(f"Brands: {len(brands)}")
    for b in brands:
        print(f"  - {b.name} | Fr: {b.fr_company}")

# Test with CSRF disabled
app.config['WTF_CSRF_ENABLED'] = False
client = app.test_client()

# Login
r = client.post('/auth/login', data={
    'username': 'admin',
    'password': 'ogcloud2024',
}, follow_redirects=True)
print(f"\nLogin + redirect: {r.status_code}")

# Check create page
r = client.get('/create')
print(f"Create page: {r.status_code}")
html = r.data.decode()
import re
brand_cards = re.findall(r'data-brand-id="(\d+)"', html)
print(f"Brand cards found: {brand_cards}")

# Test creating a quote via JSON
r = client.post('/create', json={
    'brand_id': 1,
    'customer_name': '佛山深盾智能科技有限公司',
    'sales_name': '测试销售',
    'quote_date': '2026-06-04',
    'validity': '30个自然日',
    'items': [
        {
            'service_name': '海外定向加速服务',
            'bandwidth': 50,
            'monthly_price': 4470,
            'period': 12,
            'remark': ''
        },
        {
            'service_name': '南宁-埃及SDWAN服务',
            'bandwidth': 100,
            'monthly_price': 8960,
            'period': 12,
            'remark': '含初装'
        }
    ]
})
print(f"\nCreate quote: {r.status_code}")
result = r.get_json()
print(f"Result: {result}")

if result and result.get('ok'):
    quote_id = result['id']
    # View detail
    r = client.get(f'/{quote_id}')
    print(f"Detail: {r.status_code}")
    
    # Check detail page content
    detail_html = r.data.decode()
    if '深盾' in detail_html:
        print("  ✅ Customer name found in detail")
    if '4,470' in detail_html or '4470' in detail_html:
        print("  ✅ Price found in detail")
    
    # Download PDF
    r = client.get(f'/{quote_id}/pdf')
    print(f"PDF: {r.status_code}, content_type={r.content_type}, size={len(r.data)} bytes")
    
    if r.status_code == 200 and r.content_type == 'application/pdf':
        pdf_path = os.path.join(os.path.dirname(__file__), 'data', 'test_quote.pdf')
        with open(pdf_path, 'wb') as f:
            f.write(r.data)
        print(f"  ✅ PDF saved to data/test_quote.pdf")

# Check index page
r = client.get('/')
print(f"\nIndex: {r.status_code}")
if '深盾' in r.data.decode():
    print("  ✅ Quote appears in list")

print("\n✅ All tests done!")
