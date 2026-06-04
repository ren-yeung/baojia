from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required
from app import db
from app.models import Brand
from werkzeug.utils import secure_filename
import os

brand_bp = Blueprint('brand', __name__, url_prefix='/brands')


@brand_bp.route('/')
@login_required
def index():
    brands = Brand.query.order_by(Brand.name).all()
    return render_template('brand/list.html', brands=brands)


@brand_bp.route('/create', methods=['GET', 'POST'])
@login_required
def create():
    if request.method == 'POST':
        name = request.form.get('name', '').strip()
        fr_company = request.form.get('fr_company', '').strip()
        quote_title = request.form.get('quote_title', 'SDWAN 服务报价单')
        validity = request.form.get('validity', '30个自然日')
        default_period = int(request.form.get('default_period', 12))

        logo_file = request.files.get('logo')
        logo_path = ''
        if logo_file and logo_file.filename:
            filename = secure_filename(logo_file.filename)
            logo_path = f'logos/{filename}'
            upload_dir = current_app.config['UPLOAD_FOLDER']
            logo_file.save(os.path.join(upload_dir, filename))

        brand = Brand(
            name=name, fr_company=fr_company, logo_path=logo_path,
            quote_title=quote_title, validity=validity, default_period=default_period
        )
        db.session.add(brand)
        db.session.commit()
        flash('品牌已添加', 'success')
        return redirect(url_for('brand.index'))

    return render_template('brand/list.html')


@brand_bp.route('/<int:brand_id>/edit', methods=['POST'])
@login_required
def edit(brand_id):
    brand = Brand.query.get_or_404(brand_id)
    brand.name = request.form.get('name', brand.name)
    brand.fr_company = request.form.get('fr_company', brand.fr_company)
    brand.quote_title = request.form.get('quote_title', brand.quote_title)
    brand.validity = request.form.get('validity', brand.validity)
    brand.default_period = int(request.form.get('default_period', brand.default_period))

    logo_file = request.files.get('logo')
    if logo_file and logo_file.filename:
        filename = secure_filename(logo_file.filename)
        brand.logo_path = f'logos/{filename}'
        upload_dir = current_app.config['UPLOAD_FOLDER']
        logo_file.save(os.path.join(upload_dir, filename))

    db.session.commit()
    flash('品牌已更新', 'success')
    return redirect(url_for('brand.index'))


@brand_bp.route('/<int:brand_id>/delete', methods=['POST'])
@login_required
def delete(brand_id):
    brand = Brand.query.get_or_404(brand_id)
    db.session.delete(brand)
    db.session.commit()
    flash('品牌已删除', 'success')
    return redirect(url_for('brand.index'))
