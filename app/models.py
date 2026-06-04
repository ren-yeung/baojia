from app import db
from flask_login import UserMixin
from datetime import datetime


def fmt_price(val):
    """格式化金额千分位"""
    try:
        return f"¥{float(val):,.2f}"
    except (TypeError, ValueError):
        return "¥0.00"


class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    display_name = db.Column(db.String(80))
    role = db.Column(db.String(20), default='sales')  # sales / admin
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class Brand(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    fr_company = db.Column(db.String(200), nullable=False)
    logo_path = db.Column(db.String(200), nullable=False)
    quote_title = db.Column(db.String(100), default='SDWAN 服务报价单')
    validity = db.Column(db.String(50), default='30个自然日')
    default_period = db.Column(db.Integer, default=12)
    billing_rule = db.Column(db.String(50), default='standard')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class Quote(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    quote_no = db.Column(db.String(30), unique=True, nullable=False)
    brand_id = db.Column(db.Integer, db.ForeignKey('brand.id'), nullable=False)
    fr_company = db.Column(db.String(200))
    customer_name = db.Column(db.String(200), nullable=False)
    sales_name = db.Column(db.String(80))
    quote_date = db.Column(db.Date, nullable=False)
    validity = db.Column(db.String(50), default='30个自然日')
    extra_note = db.Column(db.Text)
    total_amount = db.Column(db.Float, default=0)
    pdf_path = db.Column(db.String(300))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    brand = db.relationship('Brand', backref='quotes')
    items = db.relationship('QuoteItem', backref='quote', cascade='all, delete-orphan')

    @property
    def total_display(self):
        return fmt_price(self.total_amount)


class QuoteItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    quote_id = db.Column(db.Integer, db.ForeignKey('quote.id'), nullable=False)
    service_name = db.Column(db.String(200), nullable=False)
    bandwidth = db.Column(db.Integer)
    monthly_price = db.Column(db.Float, default=0)
    period = db.Column(db.Integer, default=12)
    annual_fee = db.Column(db.Float, default=0)
    remark = db.Column(db.String(300))
    sort_order = db.Column(db.Integer, default=0)

    @property
    def price_display(self):
        return fmt_price(self.monthly_price)

    @property
    def annual_display(self):
        return fmt_price(self.annual_fee)

    def to_dict(self):
        """Convert to dict for PDF merging"""
        return {
            'service_name': self.service_name,
            'bandwidth': self.bandwidth,
            'monthly_price': self.monthly_price,
            'period': self.period,
            'annual_fee': self.annual_fee,
            'remark': self.remark,
            'sort_order': self.sort_order,
            'show_name': True,
        }
