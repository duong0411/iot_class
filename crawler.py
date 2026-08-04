import os
import sys
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin
import re
import time

# Đặt encoding stdout thành utf-8 để in ra tiếng Việt không bị lỗi trên Windows console
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

def sanitize_filename(name):
    # Loại bỏ các ký tự không hợp lệ cho tên thư mục/file trên Windows
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()

def get_article_links(base_url, max_pages):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    article_links = set()
    
    print(f"Bắt đầu quét các trang (pagination) để tìm link bài viết từ {base_url}...")
    for page in range(1, max_pages + 1):
        # Tạo URL cho trang
        if page == 1:
            url = base_url
        else:
            url = urljoin(base_url, f"page/{page}/")
            
        try:
            res = requests.get(url, headers=headers, timeout=10)
            # Nếu web báo 404 (không tìm thấy trang) nghĩa là đã hết trang
            if res.status_code == 404:
                print(f"Đã hết trang ở page {page-1}")
                break
            res.raise_for_status()
        except Exception as e:
            print(f"Lỗi khi truy cập page {page}: {e}")
            break
            
        soup = BeautifulSoup(res.text, 'html.parser')
        links_found_on_page = 0
        for a in soup.find_all('a', href=True):
            href = a['href']
            if not href.startswith('http'):
                href = urljoin(base_url, href)
            
            # Kiểm tra link có thuộc base_url không và độ dài đủ lớn (thường là link bài)
            if base_url in href and len(href) > len(base_url) + 5:
                # Loại bỏ các trang tag, category, author, form liên hệ...
                if not any(x in href.lower() for x in ['/tag/', '/category/', '/author/', '/about', '/contact', '/page/', '/search/']):
                    if href not in article_links:
                        article_links.add(href)
                        links_found_on_page += 1
                        
        print(f"  -> Quét xong page {page}: tìm thấy thêm {links_found_on_page} link mới (Tổng đang có: {len(article_links)})")
        # Nghỉ 0.5s để tránh bị block IP do request quá nhiều
        time.sleep(0.5)
        
    return list(article_links)

def crawl_site(base_url, site_name, max_pages=50, max_articles=1000):
    print(f"\n[{site_name}] Bắt đầu tiến trình thu thập lượng lớn dữ liệu...")
    
    # 1. Quét tìm tất cả các đường dẫn bài viết
    article_links = get_article_links(base_url, max_pages)
    
    # Giới hạn số lượng bài viết lấy về
    if len(article_links) > max_articles:
        article_links = article_links[:max_articles]
        
    print(f"[{site_name}] Chốt danh sách: Sẽ crawl tổng cộng {len(article_links)} bài viết.")

    # 2. Bắt đầu crawl từng bài
    site_folder = os.path.join('data_crawl', site_name)
    if not os.path.exists(site_folder):
        os.makedirs(site_folder)

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }

    for i, link in enumerate(article_links):
        print(f"[{site_name}] {i+1}/{len(article_links)}: Đang crawl {link}")
        try:
            res = requests.get(link, headers=headers, timeout=15)
            res.raise_for_status()
            art_soup = BeautifulSoup(res.text, 'html.parser')
            
            title_tag = art_soup.find('h1')
            title = title_tag.text.strip() if title_tag else f"Article_No_Title_{i+1}"
            
            folder_name = sanitize_filename(title)
            # Cắt bớt tên thư mục nếu quá dài để tránh lỗi hệ điều hành Windows
            if len(folder_name) > 100:
                folder_name = folder_name[:100] + "..."
                
            article_folder = os.path.join(site_folder, folder_name)
            
            if not os.path.exists(article_folder):
                os.makedirs(article_folder)
            
            content_div = art_soup.find('article') or art_soup.find('main') or art_soup.find('body')
            paragraphs = content_div.find_all('p') if content_div else art_soup.find_all('p')
            
            content_text = "\n\n".join([p.text.strip() for p in paragraphs if p.text.strip()])
            
            txt_path = os.path.join(article_folder, "content.txt")
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(f"Tiêu đề: {title}\n")
                f.write(f"Đường dẫn: {link}\n")
                f.write(f"{'-'*50}\n\n")
                f.write(content_text)
                
            images = content_div.find_all('img') if content_div else art_soup.find_all('img')
            img_count = 0
            
            for img in images:
                img_url = img.get('src') or img.get('data-src') or img.get('srcset')
                if not img_url:
                    continue
                if ',' in img_url:
                    img_url = img_url.split(',')[0].split(' ')[0]
                if not img_url.startswith('http'):
                    img_url = urljoin(base_url, img_url)
                    
                valid_exts = ['.jpg', '.jpeg', '.png', '.webp', '.gif']
                if any(ext in img_url.lower() for ext in valid_exts):
                    try:
                        img_res = requests.get(img_url, headers=headers, timeout=10)
                        img_res.raise_for_status()
                        
                        ext = img_url.split('.')[-1].split('?')[0].lower()
                        if ext not in [e.strip('.') for e in valid_exts]:
                            ext = "jpg"
                            
                        img_name = f"image_{img_count+1}.{ext}"
                        img_path = os.path.join(article_folder, img_name)
                        
                        with open(img_path, "wb") as f:
                            f.write(img_res.content)
                        img_count += 1
                        
                        # Tăng giới hạn lên 20 ảnh/bài
                        if img_count >= 20:
                            break
                    except Exception as e:
                        pass
                        
            print(f"     => Đã lưu {len(paragraphs)} đoạn văn, {img_count} hình ảnh.")
            # Nghỉ ngơi 0.5 giây giữa các bài để không làm quá tải web (tránh bị block)
            time.sleep(0.5)
            
        except Exception as e:
            print(f"     => Lỗi khi crawl link {link}: {e}")

if __name__ == "__main__":
    urls_to_crawl = [
        {"url": "https://www.science-sparks.com/", "name": "Science_Sparks"},
        {"url": "https://www.snexplores.org/", "name": "Science_News_Explores"}
    ]
    
    # Cài đặt Quét qua 50 trang của mỗi web (thường mỗi trang có 10 bài -> tìm được hàng trăm bài)
    MAX_PAGES_TO_SCAN = 50 
    
    # Giới hạn lấy tối đa 500 bài viết mỗi trang web
    MAX_ARTICLES_PER_SITE = 500
    
    print("=== BẮT ĐẦU CRAWL SỐ LƯỢNG LỚN DỮ LIỆU ===")
    for site in urls_to_crawl:
        crawl_site(site["url"], site["name"], max_pages=MAX_PAGES_TO_SCAN, max_articles=MAX_ARTICLES_PER_SITE)
        
    print("\n=== HOÀN TẤT! Dữ liệu đã được lưu trong thư mục 'data_crawl' ===")
