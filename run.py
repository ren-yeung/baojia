from app import create_app, db
from app.models import User
from werkzeug.security import generate_password_hash

app = create_app()

with app.app_context():
    # Create default admin user if not exists
    if User.query.filter_by(username='admin').first() is None:
        admin = User(
            username='admin',
            password_hash=generate_password_hash('ogcloud2024'),
            display_name='管理员',
            role='admin'
        )
        db.session.add(admin)

        sales = User(
            username='sales',
            password_hash=generate_password_hash('sales2024'),
            display_name='销售',
            role='sales'
        )
        db.session.add(sales)
        db.session.commit()
        print('✅ Default users created: admin/ogcloud2024, sales/sales2024')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
