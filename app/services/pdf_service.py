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
    """同服务名多行，服务内容列和备注列只在第一行显示，备注合并"""
    result = []
    prev_name = None
    group_remarks = []
    for item in items:
        d = item.to_dict() if hasattr(item, 'to_dict') else dict(item)
        # 添加显示用的格式化字段
        d['monthly_display'] = format_price(d.get('monthly_price', 0))
        d['annual_display'] = format_price(d.get('annual_fee', 0))

        is_first = (d['service_name'] != prev_name)
        d['show_name'] = is_first

        if is_first:
            # 新组开始，合并上一组的备注
            if result and group_remarks:
                merged_remark = '、'.join(r for r in group_remarks if r)
                start_idx = len(result) - len(group_remarks)
                result[start_idx]['remark'] = merged_remark
                for i in range(1, len(group_remarks)):
                    result[start_idx + i]['remark'] = ''
            group_remarks = [d.get('remark', '')]
        else:
            group_remarks.append(d.get('remark', ''))

        result.append(d)
        prev_name = d['service_name']

    # 处理最后一组
    if result and group_remarks:
        merged_remark = '、'.join(r for r in group_remarks if r)
        start_idx = len(result) - len(group_remarks)
        result[start_idx]['remark'] = merged_remark
        for i in range(1, len(group_remarks)):
            result[start_idx + i]['remark'] = ''

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
