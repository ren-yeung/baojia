#!/bin/bash
# 报价系统一键部署脚本
# 适用于 Ubuntu 服务器
# 用法: bash deploy.sh

set -e

echo "=========================================="
echo "  报价系统 (Quote System) 一键部署"
echo "=========================================="

# 1. 安装 Docker
if ! command -v docker &> /dev/null; then
    echo "[1/6] 安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker 安装完成"
else
    echo "[1/6] Docker 已安装，跳过"
fi

# 2. 安装 docker-compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "[2/6] 安装 docker-compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "[2/6] docker-compose 已安装，跳过"
fi

# 3. 创建项目目录
echo "[3/6] 创建项目目录..."
sudo mkdir -p /opt/quote-system
cd /opt/quote-system

# 4. 创建项目文件
echo "[4/6] 创建项目文件..."

# --- config.py ---
cat > config.py << 'PYEOF'
import os
BASE_DIR = os.path.abspath(os.path.dirname(__file__))
class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'ogcloud-quote-2024-secret')
    SQLALCHEMY_DATABASE_URI = 'sqlite:///' + os.path.join(BASE_DIR, 'data', 'quote.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'app', 'static')
PYEOF

# --- app/__init__.py ---
mkdir -p app/routes app/static/logos app/templates/quote app/templates/auth

cat > app/__init__.py << 'PYEOF'
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_wtf.csrf import CSRFProtect
import os

db = SQLAlchemy()
login_manager = LoginManager()
csrf = CSRFProtect()
login_manager.login_view = 'auth.login'

def create_app():
    app = Flask(__name__)
    app.config.from_object('config.Config')
    os.makedirs(os.path.join(app.root_path, '..', 'data'), exist_ok=True)
    os.makedirs(os.path.join(app.root_path, '..', 'pdf_output'), exist_ok=True)
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
    db.init_app(app)
    login_manager.init_app(app)
    csrf.init_app(app)
    from app.routes.auth import auth_bp
    from app.routes.quote import quote_bp
    from app.routes.brand import brand_bp
    app.register_blueprint(auth_bp)
    app.register_blueprint(quote_bp)
    app.register_blueprint(brand_bp)
    with app.app_context():
        db.create_all()
        from app.models import Brand
        if Brand.query.count() == 0:
            _seed_brands()
    return app

def _seed_brands():
    from app.models import Brand
    brands = [
        Brand(name='OgCloud', fr_company='广东天耘科技有限公司', logo_path='logos/ogcloud.png',
              quote_title='SDWAN 服务报价单', validity='30个自然日', default_period=12),
        Brand(name='中国移动', fr_company='中国移动通信集团广东有限公司佛山分公司', logo_path='logos/cmcc.png',
              quote_title='SDWAN 服务报价单', validity='30个自然日', default_period=12),
        Brand(name='中国联通', fr_company='中国联合网络通信有限公司广西壮族自治区分公司', logo_path='logos/cucc.png',
              quote_title='SDWAN 服务报价单', validity='30个自然日', default_period=12),
        Brand(name='中国电信', fr_company='中国电信集团', logo_path='logos/ctcc.png',
              quote_title='SDWAN 服务报价单', validity='30个自然日', default_period=12),
    ]
    db.session.add_all(brands)
    db.session.commit()
PYEOF

# --- app/models.py ---
cat > app/models.py << 'PYEOF'
from app import db, login_manager
from flask_login import UserMixin
from datetime import datetime

def fmt_price(value):
    if value is None:
        return '¥0.00'
    return '¥{:,.2f}'.format(value)

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(200), nullable=False)
    is_admin = db.Column(db.Boolean, default=False)
    quotes = db.relationship('Quote', backref='user', lazy=True)

    @login_manager.user_loader
    def load_user(user_id):
        return User.query.get(int(user_id))

class Brand(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    fr_company = db.Column(db.String(200), nullable=False)
    logo_path = db.Column(db.String(200), nullable=False)
    quote_title = db.Column(db.String(100), default='SDWAN 服务报价单')
    validity = db.Column(db.String(50), default='30个自然日')
    default_period = db.Column(db.Integer, default=12)
    quotes = db.relationship('Quote', backref='brand', lazy=True)

class Quote(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    brand_id = db.Column(db.Integer, db.ForeignKey('brand.id'), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    to_company = db.Column(db.String(200), nullable=False)
    quote_date = db.Column(db.Date, default=datetime.utcnow)
    total_amount = db.Column(db.Float, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    items = db.relationship('QuoteItem', backref='quote', lazy=True, cascade='all, delete-orphan')

    @property
    def total_display(self):
        return fmt_price(self.total_amount)

class QuoteItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    quote_id = db.Column(db.Integer, db.ForeignKey('quote.id'), nullable=False)
    service_name = db.Column(db.String(200), nullable=False)
    bandwidth = db.Column(db.Integer, default=0)
    monthly_rent = db.Column(db.Float, default=0)
    service_period = db.Column(db.Integer, default=12)
    annual_fee = db.Column(db.Float, default=0)
    remark = db.Column(db.String(500), default='')
    sort_order = db.Column(db.Integer, default=0)

    @property
    def price_display(self):
        return fmt_price(self.monthly_rent)

    @property
    def annual_display(self):
        return fmt_price(self.annual_fee)
PYEOF

# --- app/routes/__init__.py ---
cat > app/routes/__init__.py << 'PYEOF'
PYEOF

# --- app/routes/auth.py ---
cat > app/routes/auth.py << 'PYEOF'
from flask import Blueprint, render_template, redirect, url_for, request, flash
from flask_login import login_user, logout_user, current_user
from app import db
from app.models import User
from werkzeug.security import generate_password_hash, check_password_hash

auth_bp = Blueprint('auth', __name__, url_prefix='/auth')

@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('quote.list_quotes'))
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        user = User.query.filter_by(username=username).first()
        if user and check_password_hash(user.password, password):
            login_user(user)
            return redirect(url_for('quote.list_quotes'))
        flash('用户名或密码错误')
    return render_template('auth/login.html')

@auth_bp.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('auth.login'))

def init_default_users():
    if User.query.count() == 0:
        admin = User(username='admin', password=generate_password_hash('ogcloud2024'), is_admin=True)
        sales = User(username='sales', password=generate_password_hash('sales2024'), is_admin=False)
        db.session.add_all([admin, sales])
        db.session.commit()
PYEOF

# --- app/routes/quote.py ---
cat > app/routes/quote.py << 'PYEOF'
from flask import Blueprint, render_template, redirect, url_for, request, flash, send_file
from flask_login import login_required, current_user
from app import db
from app.models import Quote, QuoteItem, Brand, fmt_price
from app.routes.auth import init_default_users
from app.services.pdf_service import generate_pdf
from datetime import datetime

quote_bp = Blueprint('quote', __name__, url_prefix='/')

@quote_bp.route('/')
@login_required
def list_quotes():
    quotes = Quote.query.filter_by(user_id=current_user.id).order_by(Quote.created_at.desc()).all()
    return render_template('quote/list.html', quotes=quotes)

@quote_bp.route('/create', methods=['GET', 'POST'])
@login_required
def create_quote():
    brands = Brand.query.all()
    if request.method == 'POST':
        brand_id = request.form.get('brand_id', type=int)
        to_company = request.form.get('to_company', '')
        service_names = request.form.getlist('service_name[]')
        bandwidths = request.form.getlist('bandwidth[]')
        monthly_rents = request.form.getlist('monthly_rent[]')
        periods = request.form.getlist('service_period[]')
        remarks = request.form.getlist('remark[]')
        quote = Quote(brand_id=brand_id, user_id=current_user.id, to_company=to_company, quote_date=datetime.now())
        total = 0
        for i in range(len(service_names)):
            if not service_names[i]:
                continue
            bw = int(bandwidths[i]) if bandwidths[i] else 0
            mr = float(monthly_rents[i]) if monthly_rents[i] else 0
            sp = int(periods[i]) if periods[i] else 12
            af = mr * sp
            total += af
            item = QuoteItem(
                service_name=service_names[i], bandwidth=bw,
                monthly_rent=mr, service_period=sp, annual_fee=af,
                remark=remarks[i] if i < len(remarks) else '', sort_order=i
            )
            quote.items.append(item)
        quote.total_amount = total
        db.session.add(quote)
        db.session.commit()
        flash('报价单创建成功')
        return redirect(url_for('quote.detail', quote_id=quote.id))
    return render_template('quote/create.html', brands=brands)

@quote_bp.route('/<int:quote_id>')
@login_required
def detail(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    from app.services.pdf_service import merge_service_rows
    merged_items = merge_service_rows(quote.items)
    return render_template('quote/detail.html', quote=quote, items=merged_items)

@quote_bp.route('/<int:quote_id>/pdf')
@login_required
def download_pdf(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    pdf_path = generate_pdf(quote)
    return send_file(pdf_path, as_attachment=True, download_name=f'报价单_{quote.to_company}_{quote.quote_date}.pdf')

@quote_bp.route('/<int:quote_id>/delete', methods=['POST'])
@login_required
def delete_quote(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    for item in quote.items:
        db.session.delete(item)
    db.session.delete(quote)
    db.session.commit()
    flash('报价单已删除')
    return redirect(url_for('quote.list_quotes'))
PYEOF

# --- app/routes/brand.py ---
cat > app/routes/brand.py << 'PYEOF'
from flask import Blueprint, render_template, redirect, url_for, request, flash
from flask_login import login_required
from app import db
from app.models import Brand

brand_bp = Blueprint('brand', __name__, url_prefix='/brands')

@brand_bp.route('/')
@login_required
def list_brands():
    brands = Brand.query.all()
    return render_template('quote/brands.html', brands=brands)
PYEOF

# --- app/services/__init__.py ---
mkdir -p app/services
cat > app/services/__init__.py << 'PYEOF'
PYEOF

# --- app/services/pdf_service.py ---
cat > app/services/pdf_service.py << 'PYEOF'
import os
from flask import current_app
from weasyprint import HTML
from app.models import fmt_price

def merge_service_rows(items):
    sorted_items = sorted(items, key=lambda x: (x.service_name, x.sort_order))
    merged = []
    i = 0
    while i < len(sorted_items):
        item = sorted_items[i]
        row = {
            'service_name': item.service_name,
            'bandwidth': item.bandwidth,
            'monthly_rent': item.monthly_rent,
            'monthly_display': item.price_display,
            'service_period': item.service_period,
            'annual_fee': item.annual_fee,
            'annual_display': item.annual_display,
            'remark': item.remark,
            'rowspan': 1,
            'show_service': True,
            'show_remark': True,
        }
        j = i + 1
        while j < len(sorted_items) and sorted_items[j].service_name == item.service_name:
            row['rowspan'] += 1
            next_item = sorted_items[j]
            merged.append({
                'service_name': next_item.service_name,
                'bandwidth': next_item.bandwidth,
                'monthly_rent': next_item.monthly_rent,
                'monthly_display': next_item.price_display,
                'service_period': next_item.service_period,
                'annual_fee': next_item.annual_fee,
                'annual_display': next_item.annual_display,
                'remark': '',
                'rowspan': 0,
                'show_service': False,
                'show_remark': False,
            })
            if next_item.remark:
                if row['remark']:
                    row['remark'] = row['remark'] + '、' + next_item.remark
                else:
                    row['remark'] = next_item.remark
            j += 1
        merged.append(row)
        i = j
    return merged

def generate_pdf(quote):
    from flask import render_template_string
    items = merge_service_rows(quote.items)
    brand = quote.brand
    logo_url = brand.logo_path
    
    html_content = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
@page { size: A4; margin: 2cm; }
body { font-family: SimSun, serif; font-size: 12pt; color: #333; }
.header { text-align: center; margin-bottom: 30px; }
.header img { height: 60px; margin-bottom: 10px; }
.header h1 { font-size: 18pt; margin: 5px 0; }
.info-table { width: 100%; margin-bottom: 20px; border: none; }
.info-table td { padding: 3px 8px; border: none; font-size: 11pt; }
.info-label { font-weight: bold; width: 80px; }
.main-table { width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 10pt; }
.main-table th, .main-table td { border: 1px solid #333; padding: 6px 8px; text-align: center; }
.main-table th { background: #f5f5f5; font-weight: bold; }
.main-table td.left { text-align: left; }
.total-row { font-weight: bold; }
.footer { text-align: right; margin-top: 30px; font-size: 11pt; }
</style>
</head>
<body>
<div class="header">
  <img src="{{ logo_path }}">
  <h1>{{ title }}</h1>
</div>
<table class="info-table">
<tr><td class="info-label">To:</td><td>{{ to_company }}</td>
    <td class="info-label">Fr:</td><td>{{ fr_company }}</td></tr>
<tr><td class="info-label"></td><td></td>
    <td class="info-label">有效期:</td><td>{{ validity }}</td></tr>
</table>
<table class="main-table">
<thead>
<tr><th>服务内容</th><th>带宽(Mbps)</th><th>月租(元/月)</th>
    <th>服务周期(月)</th><th>年服务费(元/年)</th><th>备注</th></tr>
</thead>
<tbody>
{% for item in items %}
<tr{% if loop.last or (loop.index < items|length and items[loop.index].service_name != item.service_name) %} class="total-row"{% endif %}>
{% if item.show_service %}
<td rowspan="{{ item.rowspan }}" class="left">{{ item.service_name }}</td>
{% endif %}
<td>{{ item.bandwidth }}</td>
<td>{{ item.monthly_display }}</td>
<td>{{ item.service_period }}</td>
<td>{{ item.annual_display }}</td>
{% if item.show_remark is defined and item.show_remark %}
<td rowspan="{{ item.rowspan }}" class="left">{{ item.remark }}</td>
{% endif %}
</tr>
{% endfor %}
</tbody>
</table>
<div class="footer">报价日期：{{ quote_date }}</div>
</body>
</html>
'''
    
    rendered = render_template_string(html_content,
        logo_path=logo_url,
        title=brand.quote_title,
        to_company=quote.to_company,
        fr_company=brand.fr_company,
        validity=brand.validity,
        items=items,
        quote_date=quote.quote_date.strftime('%Y年%m月%d日') if quote.quote_date else '',
        total=fmt_price(quote.total_amount)
    )
    
    output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'pdf_output')
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f'quote_{quote.id}.pdf')
    HTML(string=rendered).write_pdf(output_path)
    return output_path
PYEOF

# --- Templates ---
# base.html
cat > app/templates/base.html << 'PYEOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>{% block title %}报价系统{% endblock %}</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f7fa; color: #333; min-height: 100vh; font-size: 14px; }
.nav { background: #fff; padding: 12px 16px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #eee; position: sticky; top: 0; z-index: 100; }
.nav-title { font-size: 17px; font-weight: 600; }
.nav-btn { color: #4a90d9; text-decoration: none; font-size: 14px; }
.container { padding: 16px; max-width: 480px; margin: 0 auto; }
.card { background: #fff; border-radius: 12px; padding: 16px; margin-bottom: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
.btn { display: inline-block; padding: 12px 24px; border-radius: 8px; border: none; font-size: 15px; cursor: pointer; text-align: center; text-decoration: none; width: 100%; }
.btn-primary { background: #4a90d9; color: #fff; }
.btn-danger { background: #e74c3c; color: #fff; }
.btn-outline { background: #fff; color: #4a90d9; border: 1px solid #4a90d9; }
.form-group { margin-bottom: 14px; }
.form-label { display: block; margin-bottom: 6px; font-size: 13px; color: #666; font-weight: 500; }
.form-input { width: 100%; padding: 10px 12px; border: 1px solid #ddd; border-radius: 8px; font-size: 15px; outline: none; }
.form-input:focus { border-color: #4a90d9; }
.alert { padding: 10px 14px; border-radius: 8px; margin-bottom: 12px; font-size: 13px; }
.alert-danger { background: #fff0f0; color: #c0392b; }
.alert-success { background: #f0fff0; color: #27ae60; }
.empty { text-align: center; padding: 40px 20px; color: #999; }
.empty-icon { font-size: 48px; margin-bottom: 12px; }
</style>
</head>
<body>
<nav class="nav">
  <a href="/" class="nav-btn" style="font-size:17px;font-weight:600;color:#333;text-decoration:none;">报价系统</a>
  {% if current_user.is_authenticated %}
  <a href="{{ url_for('auth.logout') }}" class="nav-btn">退出</a>
  {% endif %}
</nav>
<div class="container">
  {% with messages = get_flashed_messages(with_categories=true) %}
  {% for category, message in messages %}
  <div class="alert alert-{{ category }}">{{ message }}</div>
  {% endfor %}
  {% endwith %}
  {% block content %}{% endblock %}
</div>
</body>
</html>
PYEOF

# login.html
cat > app/templates/auth/login.html << 'PYEOF'
{% extends "base.html" %}
{% block title %}登录 - 报价系统{% endblock %}
{% block content %}
<div style="padding-top:40px;">
  <div style="text-align:center;margin-bottom:30px;">
    <div style="font-size:32px;font-weight:700;color:#4a90d9;">报价系统</div>
    <div style="font-size:13px;color:#999;margin-top:6px;">SDWAN服务报价管理</div>
  </div>
  <form method="POST">
    <input type="hidden" name="csrf_token" value="{{ csrf_token() }}">
    <div class="form-group">
      <label class="form-label">用户名</label>
      <input type="text" name="username" class="form-input" placeholder="请输入用户名" required>
    </div>
    <div class="form-group">
      <label class="form-label">密码</label>
      <input type="password" name="password" class="form-input" placeholder="请输入密码" required>
    </div>
    <button type="submit" class="btn btn-primary" style="margin-top:10px;">登 录</button>
  </form>
</div>
{% endblock %}
PYEOF

# list.html
cat > app/templates/quote/list.html << 'PYEOF'
{% extends "base.html" %}
{% block title %}报价单列表{% endblock %}
{% block content %}
<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
  <span style="font-size:18px;font-weight:600;">报价单</span>
  <a href="{{ url_for('quote.create_quote') }}" class="btn btn-primary" style="width:auto;padding:8px 20px;font-size:14px;">+ 新建</a>
</div>
{% if quotes %}
{% for q in quotes %}
<a href="{{ url_for('quote.detail', quote_id=q.id) }}" style="text-decoration:none;color:inherit;">
<div class="card" style="display:flex;justify-content:space-between;align-items:center;">
  <div>
    <div style="font-weight:600;font-size:15px;">{{ q.to_company }}</div>
    <div style="font-size:12px;color:#999;margin-top:4px;">{{ q.brand.name }} | {{ q.quote_date.strftime('%Y-%m-%d') }}</div>
  </div>
  <div style="font-weight:600;color:#4a90d9;">{{ q.total_display }}</div>
</div>
</a>
{% endfor %}
{% else %}
<div class="empty">
  <div class="empty-icon">📋</div>
  <div>暂无报价单</div>
  <div style="margin-top:8px;font-size:13px;">点击右上角新建</div>
</div>
{% endif %}
{% endblock %}
PYEOF

# create.html
cat > app/templates/quote/create.html << 'PYEOF'
{% extends "base.html" %}
{% block title %}新建报价单{% endblock %}
{% block content %}
<form method="POST" id="quoteForm">
<input type="hidden" name="csrf_token" value="{{ csrf_token() }}">
<div class="card">
  <div class="form-group">
    <label class="form-label">选择品牌</label>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
    {% for b in brands %}
    <label style="display:flex;align-items:center;padding:10px;border:2px solid #eee;border-radius:8px;cursor:pointer;" class="brand-option" data-id="{{ b.id }}" onclick="selectBrand(this)">
      <input type="radio" name="brand_id" value="{{ b.id }}" style="display:none;" required>
      <span style="font-size:13px;font-weight:500;">{{ b.name }}</span>
    </label>
    {% endfor %}
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">To (客户公司)</label>
    <input type="text" name="to_company" class="form-input" placeholder="请输入客户公司名称" required>
  </div>
</div>
<div class="card">
  <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
    <span style="font-weight:600;">服务明细</span>
    <button type="button" onclick="addRow()" class="btn btn-outline" style="width:auto;padding:6px 14px;font-size:13px;">+ 添加</button>
  </div>
  <div id="items"></div>
</div>
<button type="submit" class="btn btn-primary" style="margin-top:8px;">生成报价单</button>
</form>
<script>
var idx = 0;
function addRow() {
  var d = document.createElement('div');
  d.className = 'item-row';
  d.style.cssText = 'background:#f8f9fa;border-radius:8px;padding:10px;margin-bottom:8px;position:relative;';
  d.innerHTML = '<button type="button" onclick="this.parentElement.remove()" style="position:absolute;top:6px;right:8px;background:none;border:none;color:#e74c3c;font-size:18px;cursor:pointer;">×</button>' +
    '<div class="form-group"><input type="text" name="service_name[]" class="form-input" placeholder="服务内容" style="font-size:13px;padding:8px;"></div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;">' +
    '<input type="number" name="bandwidth[]" class="form-input" placeholder="带宽Mbps" style="font-size:13px;padding:8px;">' +
    '<input type="number" name="monthly_rent[]" class="form-input" placeholder="月租(元)" step="0.01" style="font-size:13px;padding:8px;">' +
    '</div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:6px;">' +
    '<input type="number" name="service_period[]" class="form-input" placeholder="周期(月)" value="12" style="font-size:13px;padding:8px;">' +
    '<input type="text" name="remark[]" class="form-input" placeholder="备注" style="font-size:13px;padding:8px;">' +
    '</div>';
  document.getElementById('items').appendChild(d);
  idx++;
}
addRow();
function selectBrand(el) {
  document.querySelectorAll('.brand-option').forEach(function(e){ e.style.borderColor='#eee'; });
  el.style.borderColor = '#4a90d9';
  el.querySelector('input').checked = true;
}
</script>
{% endblock %}
PYEOF

# detail.html
cat > app/templates/quote/detail.html << 'PYEOF'
{% extends "base.html" %}
{% block title %}报价单详情{% endblock %}
{% block content %}
<div class="card">
  <div style="text-align:center;margin-bottom:12px;">
    <img src="{{ url_for('static', filename=quote.brand.logo_path) }}" style="height:40px;margin-bottom:6px;" onerror="this.style.display='none'">
    <div style="font-size:16px;font-weight:600;">{{ quote.brand.quote_title }}</div>
  </div>
  <div style="font-size:13px;color:#666;line-height:1.8;">
    <div><strong>To:</strong> {{ quote.to_company }}</div>
    <div><strong>Fr:</strong> {{ quote.brand.fr_company }}</div>
    <div><strong>有效期:</strong> {{ quote.brand.validity }}</div>
  </div>
</div>
<div class="card">
  <div style="overflow-x:auto;">
    <table style="width:100%;border-collapse:collapse;font-size:12px;">
      <thead><tr style="background:#f5f5f5;">
        <th style="padding:8px;border:1px solid #ddd;">服务内容</th>
        <th style="padding:8px;border:1px solid #ddd;">带宽</th>
        <th style="padding:8px;border:1px solid #ddd;">月租</th>
        <th style="padding:8px;border:1px solid #ddd;">周期</th>
        <th style="padding:8px;border:1px solid #ddd;">年费</th>
        <th style="padding:8px;border:1px solid #ddd;">备注</th>
      </tr></thead>
      <tbody>
      {% for item in items %}
      <tr>
        {% if item.show_service %}<td rowspan="{{ item.rowspan }}" style="padding:6px;border:1px solid #ddd;text-align:left;">{{ item.service_name }}</td>{% endif %}
        <td style="padding:6px;border:1px solid #ddd;text-align:center;">{{ item.bandwidth }}</td>
        <td style="padding:6px;border:1px solid #ddd;text-align:center;">{{ item.monthly_display }}</td>
        <td style="padding:6px;border:1px solid #ddd;text-align:center;">{{ item.service_period }}</td>
        <td style="padding:6px;border:1px solid #ddd;text-align:center;">{{ item.annual_display }}</td>
        {% if item.show_remark %}<td rowspan="{{ item.rowspan }}" style="padding:6px;border:1px solid #ddd;text-align:left;">{{ item.remark }}</td>{% endif %}
      </tr>
      {% endfor %}
      <tr style="font-weight:600;background:#f9f9f9;">
        <td colspan="4" style="padding:8px;border:1px solid #ddd;text-align:right;">合计</td>
        <td style="padding:8px;border:1px solid #ddd;text-align:center;">{{ quote.total_display }}</td>
        <td style="padding:8px;border:1px solid #ddd;"></td>
      </tr>
      </tbody>
    </table>
  </div>
  <div style="text-align:right;margin-top:12px;font-size:13px;color:#666;">报价日期：{{ quote.quote_date.strftime('%Y年%m月%d日') }}</div>
</div>
<div style="display:flex;gap:8px;margin-top:8px;">
  <a href="{{ url_for('quote.download_pdf', quote_id=quote.id) }}" class="btn btn-primary" style="flex:1;">下载PDF</a>
  <form method="POST" action="{{ url_for('quote.delete_quote', quote_id=quote.id) }}" style="flex:1;" onsubmit="return confirm('确定删除？')">
    <input type="hidden" name="csrf_token" value="{{ csrf_token() }}">
    <button type="submit" class="btn btn-danger" style="width:100%;">删除</button>
  </form>
</div>
{% endblock %}
PYEOF

# brands.html
cat > app/templates/quote/brands.html << 'PYEOF'
{% extends "base.html" %}
{% block title %}品牌管理{% endblock %}
{% block content %}
<div style="font-size:18px;font-weight:600;margin-bottom:16px;">品牌管理</div>
{% for b in brands %}
<div class="card" style="display:flex;align-items:center;gap:12px;">
  <img src="{{ url_for('static', filename=b.logo_path) }}" style="height:32px;" onerror="this.style.display='none'">
  <div>
    <div style="font-weight:600;">{{ b.name }}</div>
    <div style="font-size:12px;color:#999;">{{ b.fr_company }}</div>
  </div>
</div>
{% endfor %}
{% endblock %}
PYEOF

# --- run.py ---
cat > run.py << 'PYEOF'
from app import create_app, db
from app.routes.auth import init_default_users

app = create_app()

with app.app_context():
    init_default_users()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# --- requirements.txt ---
cat > requirements.txt << 'PYEOF'
flask==3.0.0
flask-sqlalchemy==3.1.1
flask-login==0.6.3
flask-wtf==1.2.1
weasyprint==60.2
gunicorn==21.2.0
PYEOF

# --- Dockerfile ---
cat > Dockerfile << 'PYEOF'
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3-dev python3-pip python3-setuptools \
    python3-wheel python3-cffi libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 libffi-dev shared-mime-info fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN mkdir -p data pdf_output
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "run:app"]
PYEOF

# --- docker-compose.yml ---
cat > docker-compose.yml << 'PYEOF'
version: '3.8'
services:
  web:
    build: .
    container_name: quote-system
    restart: always
    volumes:
      - ./data:/app/data
      - ./pdf_output:/app/pdf_output
      - ./app/static/logos:/app/app/static/logos
    ports:
      - "5000:5000"
PYEOF

# 5. 复制SSL证书和Nginx配置
echo "[5/6] 配置Nginx和SSL..."

# SSL证书目录
sudo mkdir -p /etc/nginx/ssl

# Nginx配置
cat > /tmp/quote-system-nginx.conf << 'NGINXEOF'
server {
    listen 80;
    server_name baojia.kuajing.space;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name baojia.kuajing.space;

    ssl_certificate /etc/nginx/ssl/kuajing.space_bundle.pem;
    ssl_certificate_key /etc/nginx/ssl/kuajing.space.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static/ {
        alias /opt/quote-system/app/static/;
        expires 7d;
    }
}
NGINXEOF

sudo cp /tmp/quote-system-nginx.conf /etc/nginx/sites-available/quote-system
sudo ln -sf /etc/nginx/sites-available/quote-system /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 6. 启动服务
echo "[6/6] 启动服务..."
cd /opt/quote-system
sudo docker compose build
sudo docker compose up -d

# 启动Nginx
sudo nginx -t && sudo systemctl restart nginx || sudo systemctl start nginx

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "访问地址: https://baojia.kuajing.space"
echo "默认账号: admin / ogcloud2024"
echo "         sales / sales2024"
echo ""
echo "⚠️  还需要手动操作:"
echo "1. 上传SSL证书到 /etc/nginx/ssl/:"
echo "   - kuajing.space_bundle.pem"
echo "   - kuajing.space.key"
echo "2. 上传Logo文件到 /opt/quote-system/app/static/logos/:"
echo "   - ogcloud.png, cmcc.png, cucc.png, ctcc.png"
echo "3. 上传完成后重启: cd /opt/quote-system && sudo docker compose restart"
echo ""
