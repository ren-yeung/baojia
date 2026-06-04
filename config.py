import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-change-in-production')
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        'DATABASE_URL',
        'sqlite:///' + os.path.join(BASE_DIR, 'data', 'quote.db')
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'app', 'static', 'logos')
    PDF_OUTPUT_FOLDER = os.path.join(BASE_DIR, 'pdf_output')
    MAX_CONTENT_LENGTH = 5 * 1024 * 1024

    # WeChat Work
    WEWORK_CORP_ID = os.environ.get('WEWORK_CORP_ID', 'ww688bc4244c844cf1')
    WEWORK_AGENT_ID = os.environ.get('WEWORK_AGENT_ID', '1000003')
    WEWORK_SECRET = os.environ.get('WEWORK_SECRET', 'UTuVo6K-ixaxJ1kcovBy9ib96CDov1wEgv0MKprevJM')
