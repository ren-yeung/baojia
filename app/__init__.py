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

    # Ensure directories exist
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
