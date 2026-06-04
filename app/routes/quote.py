from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify, send_file, current_app
from flask_login import login_required, current_user
from app import db
from app.models import Quote, QuoteItem, Brand
from datetime import date
import json

quote_bp = Blueprint('quote', __name__, url_prefix='/')


@quote_bp.route('/')
@login_required
def index():
    page = request.args.get('page', 1, type=int)
    per_page = 15
    if current_user.is_admin:
        query = Quote.query.order_by(Quote.created_at.desc())
    else:
        query = Quote.query.filter_by(user_id=current_user.id).order_by(Quote.created_at.desc())
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    return render_template('quote/list.html', quotes=pagination.items, pagination=pagination)


@quote_bp.route('/create', methods=['GET', 'POST'])
@login_required
def create():
    brands = Brand.query.order_by(Brand.name).all()
    if request.method == 'POST':
        data = request.get_json(silent=True) or request.form
        brand_id = int(data.get('brand_id'))
        brand = Brand.query.get(brand_id)
        customer_name = data.get('customer_name', '').strip()
        fr_company = data.get('fr_company', '').strip()
        sales_name = data.get('sales_name', '').strip()
        quote_date_str = data.get('quote_date', date.today().isoformat())
        validity = data.get('validity', '30 Days')
        extra_note = data.get('extra_note', '').strip()
        if not customer_name:
            return jsonify({'ok': False, 'msg': 'Customer name is required'}), 400
        quote_date = date.fromisoformat(quote_date_str) if isinstance(quote_date_str, str) else quote_date_str
        quote_no = _gen_quote_no()
        quote = Quote(
            quote_no=quote_no, brand_id=brand_id,
            fr_company=fr_company or brand.fr_company,
            customer_name=customer_name,
            sales_name=sales_name or (current_user.display_name if current_user else ''),
            quote_date=quote_date, validity=validity,
            extra_note=extra_note, user_id=current_user.id
        )
        db.session.add(quote)
        db.session.flush()
        items_raw = data.get('items', [])
        if isinstance(items_raw, str):
            items_raw = json.loads(items_raw)
        total = 0
        for i, item in enumerate(items_raw):
            monthly = float(item.get('monthly_price', 0))
            period = int(item.get('period', 12))
            annual = monthly * period
            total += annual
            qi = QuoteItem(
                quote_id=quote.id,
                service_name=item.get('service_name', '').strip(),
                bandwidth=int(item.get('bandwidth', 0)) if item.get('bandwidth') else None,
                monthly_price=monthly, period=period, annual_fee=annual,
                remark=item.get('remark', '').strip(), sort_order=i
            )
            db.session.add(qi)
        quote.total_amount = total
        db.session.commit()
        return jsonify({'ok': True, 'quote_no': quote_no, 'id': quote.id})
    return render_template('quote/create.html', brands=brands, today=date.today().isoformat())


@quote_bp.route('/<int:quote_id>')
@login_required
def detail(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    if not current_user.is_admin and quote.user_id != current_user.id:
        flash('No permission to view this quote', 'error')
        return redirect(url_for('quote.index'))
    items = sorted(quote.items, key=lambda x: x.sort_order)
    from app.services.pdf_service import merge_service_rows
    merged = merge_service_rows(items)
    return render_template('quote/detail.html', quote=quote, merged_items=merged)


@quote_bp.route('/<int:quote_id>/pdf')
@login_required
def download_pdf(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    if not current_user.is_admin and quote.user_id != current_user.id:
        return jsonify({'ok': False, 'msg': 'Permission denied'}), 403
    items = sorted(quote.items, key=lambda x: x.sort_order)
    from app.services.pdf_service import generate_pdf
    pdf_bytes = generate_pdf(quote, items, quote.brand)
    filename = "{}_{}_{}.pdf".format(quote.brand.name, quote.customer_name, quote.quote_no)
    from io import BytesIO
    as_attachment = request.args.get('inline', '0') != '1'
    return send_file(
        BytesIO(pdf_bytes), mimetype='application/pdf',
        as_attachment=as_attachment,
        download_name=filename if as_attachment else None
    )


@quote_bp.route('/<int:quote_id>/delete', methods=['POST'])
@login_required
def delete(quote_id):
    quote = Quote.query.get_or_404(quote_id)
    if not current_user.is_admin and quote.user_id != current_user.id:
        flash('No permission to delete this quote', 'error')
        return redirect(url_for('quote.index'))
    db.session.delete(quote)
    db.session.commit()
    flash('Quote deleted', 'success')
    return redirect(url_for('quote.index'))


def _gen_quote_no():
    today = date.today().strftime('%Y%m%d')
    count = Quote.query.filter(Quote.quote_no.like('QT-{}%'.format(today))).count() + 1
    return 'QT-{}-{:03d}'.format(today, count)
