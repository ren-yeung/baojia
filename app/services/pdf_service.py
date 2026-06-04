from flask import current_app
from weasyprint import HTML
from jinja2 import Environment, FileSystemLoader
import os


def format_price(value):
    """格式化金额：千分位 + 两位小数"""
    try:
        return f"¥{float(value):,.2f}"
    except (TypeError, ValueError):
        return "¥0.00"


def merge_service_rows(items):
    """同服务名多行，服务内容列和备注列用rowspan合并，备注分行显示"""
    result = []
    prev_name = None
    group_start_idx = None
    group_count = 0
    group_remarks = []

    for item in items:
        d = item.to_dict() if hasattr(item, 'to_dict') else dict(item)
        d['monthly_display'] = format_price(d.get('monthly_price', 0))
        d['annual_display'] = format_price(d.get('annual_fee', 0))

        if d['service_name'] != prev_name:
            # 上一组结束，设置rowspan和合并备注
            if group_start_idx is not None:
                result[group_start_idx]['rowspan'] = group_count
                # 备注分行显示
                remark_lines = [r for r in group_remarks if r]
                result[group_start_idx]['remark_display'] = '<br>'.join(remark_lines)
                result[group_start_idx]['is_merge_start'] = True
                for i in range(1, group_count):
                    result[group_start_idx + i]['is_merge_cont'] = True

            # 新组开始
            group_start_idx = len(result)
            group_count = 1
            group_remarks = [d.get('remark', '')]
            d['rowspan'] = 1
            d['is_merge_start'] = False
            d['is_merge_cont'] = False
            d['remark_display'] = d.get('remark', '')
        else:
            group_count += 1
            group_remarks.append(d.get('remark', ''))
            d['rowspan'] = 0
            d['is_merge_start'] = False
            d['is_merge_cont'] = True
            d['remark_display'] = ''

        result.append(d)
        prev_name = d['service_name']

    # 最后一组
    if group_start_idx is not None:
        result[group_start_idx]['rowspan'] = group_count
        remark_lines = [r for r in group_remarks if r]
        result[group_start_idx]['remark_display'] = '<br>'.join(remark_lines)
        result[group_start_idx]['is_merge_start'] = True
        for i in range(1, group_count):
            result[group_start_idx + i]['is_merge_cont'] = True

    return result


def generate_pdf(quote, items, brand):
    """生成报价单PDF"""
    template_dir = os.path.join(current_app.root_path, '..', 'pdf_templates')
    env = Environment(loader=FileSystemLoader(template_dir))
    env.filters['format_price'] = format_price
    template = env.get_template('sdwan_quote.html')

    logo_abs = os.path.join(current_app.root_path, 'static', brand.logo_path)

    sorted_items = sorted(items, key=lambda x: x.sort_order)
    merged = merge_service_rows(sorted_items)

    total = sum(item.annual_fee for item in sorted_items)

    html_content = template.render(
        brand=brand,
        quote=quote,
        items=merged,
        total=total,
        logo_abs=logo_abs,
    )

    pdf_bytes = HTML(string=html_content).write_pdf()
    return pdf_bytes
