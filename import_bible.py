import os
import sys
import pymysql
import xml.etree.ElementTree as ET
import requests
from pathlib import Path
import zipfile
import shutil

def download_bibles():
    """下载圣经数据"""
    print("下载圣经数据...")
    url = "https://github.com/seven1m/open-bibles/archive/refs/heads/master.zip"
    response = requests.get(url)
    print(f"下载状态: {response.status_code}")
    
    with open("bibles.zip", "wb") as f:
        f.write(response.content)
    print(f"保存zip文件: {os.path.getsize('bibles.zip')} 字节")
    
    print("解压文件...")
    with zipfile.ZipFile("bibles.zip", "r") as zip_ref:
        # 打印zip文件内容
        print("\nZIP文件内容:")
        for file in zip_ref.namelist():
            print(f"  {file}")
        zip_ref.extractall(".")
    
    print("\n解压后的文件:")
    os.system("ls -la open-bibles-master/*.xml")
    
    if os.path.exists("bibles"):
        print("删除旧的bibles目录")
        shutil.rmtree("bibles")
    
    # 创建bibles目录并移动XML文件
    os.makedirs("bibles", exist_ok=True)
    for xml_file in Path("open-bibles-master").glob("*.xml"):
        shutil.copy2(xml_file, "bibles/")
    
    print("\n最终的bibles目录内容:")
    os.system("ls -la bibles/")
    
    print("\n清理临时文件")
    os.remove("bibles.zip")
    shutil.rmtree("open-bibles-master")

def create_tables(cursor):
    """创建必要的数据库表"""
    print("创建数据库表...")
    
    # 删除旧表
    cursor.execute("DROP TABLE IF EXISTS verses")
    cursor.execute("DROP TABLE IF EXISTS translations")
    
    cursor.execute("""
    CREATE TABLE translations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        identifier VARCHAR(50) NOT NULL,
        language VARCHAR(20) NOT NULL,
        name VARCHAR(100) NOT NULL,
        language_code VARCHAR(20) NOT NULL,
        license TEXT
    )
    """)

    cursor.execute("""
    CREATE TABLE verses (
        id INT AUTO_INCREMENT PRIMARY KEY,
        translation_id INT NOT NULL,
        book_id VARCHAR(20) NOT NULL,
        book VARCHAR(100) NOT NULL,
        chapter INT NOT NULL,
        verse INT NOT NULL,
        text TEXT NOT NULL,
        FOREIGN KEY (translation_id) REFERENCES translations(id)
    )
    """)

def analyze_xml(file_path):
    """分析XML文件结构"""
    print(f"\n分析 {file_path} 的结构...")
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    print(f"根元素: {root.tag}")
    # 打印命名空间
    namespaces = {k:v for k,v in root.items() if k.startswith('xmlns')}
    print("命名空间:", namespaces)
    
    # 打印前几个子元素
    for child in list(root)[:2]:
        print(f"\n子元素: {child.tag}")
        for attr, value in child.items():
            print(f"  属性: {attr} = {value}")
        if len(list(child)) > 0:
            print("  第一个孙元素:", list(child)[0].tag)

def get_first_number(text):
    """从可能包含范围的文本中提取第一个数字"""
    if not text:
        return None
    # 处理类似 "9-20" 的格式，只取第一个数字
    number = text.split('-')[0]
    try:
        return int(number)
    except ValueError:
        return None

def get_text_content(elem):
    """获取元素的所有文本内容，忽略标签"""
    text = ''
    if elem.text:
        text += elem.text.strip() + ' '
    for child in elem:
        text += get_text_content(child)
        if child.tail:
            text += child.tail.strip() + ' '
    return text.strip()

def import_bible(cursor, bible_file):
    """导入单个圣经文件"""
    print(f"\n导入 {bible_file}...")
    
    try:
        # 从文件名解析翻译信息
        filename = Path(bible_file).stem
        parts = filename.split('-')
        lang = parts[0]
        # 移除文件扩展名后缀（.usfx, .osis等）
        trans = parts[1].split('.')[0]
        print(f"语言: {lang}, 翻译: {trans}")
        
        # 插入翻译信息
        cursor.execute("""
        INSERT INTO translations (identifier, language, name, language_code, license)
        VALUES (%s, %s, %s, %s, %s)
        """, (trans, lang, f"{lang.upper()} - {trans.upper()}", lang, "Public Domain"))
        
        translation_id = cursor.lastrowid
        print(f"创建翻译ID: {translation_id}")
        
        # 解析XML
        parser = ET.XMLParser(encoding="utf-8")
        tree = ET.parse(bible_file, parser=parser)
        root = tree.getroot()
        print(f"XML根元素: {root.tag}")
        
        # 遍历并插入经文
        verse_count = 0
        current_book = None
        current_chapter = None
        
        # USFX格式
        if root.tag == 'usfx':
            print("使用USFX格式")
            for elem in root.iter():
                if elem.tag == 'book':
                    current_book = elem.get('id')
                    print(f"处理书卷: {current_book}")
                elif elem.tag == 'c' and current_book:
                    try:
                        current_chapter = int(elem.get('id', '0'))
                    except ValueError:
                        continue
                elif elem.tag == 'v' and current_book and current_chapter:
                    try:
                        verse_num = int(elem.get('id', '0'))
                        verse_text = get_text_content(elem)
                        
                        if verse_text:
                            cursor.execute("""
                            INSERT INTO verses (translation_id, book_id, book, chapter, verse, text)
                            VALUES (%s, %s, %s, %s, %s, %s)
                            """, (translation_id, current_book, current_book, 
                                  current_chapter, verse_num, verse_text))
                            verse_count += 1
                            
                            if verse_count % 1000 == 0:
                                print(f"已导入 {verse_count} 节经文...")
                                cursor.connection.commit()
                    except ValueError:
                        continue
        
        # OSIS格式
        elif 'osis' in root.tag.lower():
            print("使用OSIS格式")
            for book in root.findall(".//{*}div[@type='book']"):
                current_book = book.get('osisID')
                if not current_book:
                    continue
                    
                print(f"处理书卷: {current_book}")
                
                for chapter in book.findall(".//{*}chapter"):
                    try:
                        chapter_id = chapter.get('osisID', '').split('.')[-1]
                        current_chapter = int(chapter_id)
                        
                        for verse in chapter.findall(".//{*}verse"):
                            try:
                                verse_id = verse.get('osisID', '').split('.')[-1]
                                verse_num = int(verse_id)
                                verse_text = get_text_content(verse)
                                
                                if verse_text:
                                    cursor.execute("""
                                    INSERT INTO verses (translation_id, book_id, book, chapter, verse, text)
                                    VALUES (%s, %s, %s, %s, %s, %s)
                                    """, (translation_id, current_book, current_book, 
                                          current_chapter, verse_num, verse_text))
                                    verse_count += 1
                                    
                                    if verse_count % 1000 == 0:
                                        print(f"已导入 {verse_count} 节经文...")
                                        cursor.connection.commit()
                            except (ValueError, IndexError):
                                continue
                    except (ValueError, IndexError):
                        continue
        
        # Zefania格式
        elif root.tag == 'XMLBIBLE':
            print("使用Zefania格式")
            for book in root.findall(".//BIBLEBOOK"):
                current_book = book.get('bnumber')
                book_name = book.get('bname')
                
                if not current_book or not book_name:
                    continue
                    
                print(f"处理书卷: {book_name}")
                
                for chapter in book.findall(".//CHAPTER"):
                    try:
                        current_chapter = int(chapter.get('cnumber', '0'))
                        
                        for verse in chapter.findall(".//VERSE"):
                            try:
                                verse_num = int(verse.get('vnumber', '0'))
                                verse_text = get_text_content(verse)
                                
                                if verse_text:
                                    cursor.execute("""
                                    INSERT INTO verses (translation_id, book_id, book, chapter, verse, text)
                                    VALUES (%s, %s, %s, %s, %s, %s)
                                    """, (translation_id, current_book, book_name, 
                                          current_chapter, verse_num, verse_text))
                                    verse_count += 1
                                    
                                    if verse_count % 1000 == 0:
                                        print(f"已导入 {verse_count} 节经文...")
                                        cursor.connection.commit()
                            except ValueError:
                                continue
                    except ValueError:
                        continue
        
        cursor.connection.commit()
        print(f"成功导入 {verse_count} 节经文")
    except Exception as e:
        print(f"导入 {bible_file} 时出错: {e}")
        cursor.connection.rollback()
        raise

def main():
    # 获取数据库连接信息
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("错误：需要设置 DATABASE_URL 环境变量")
        sys.exit(1)
    
    # 解析数据库URL
    # 格式：mysql2://user:pass@host:port/dbname
    db_info = {}
    db_info['user'] = db_url.split('://')[1].split(':')[0]
    db_info['password'] = db_url.split('@')[0].split(':')[-1]
    db_info['host'] = db_url.split('@')[1].split(':')[0]
    db_info['port'] = int(db_url.split(':')[-1].split('/')[0])
    db_info['database'] = db_url.split('/')[-1].split('?')[0]
    
    print("连接数据库...")
    conn = pymysql.connect(
        host=db_info['host'],
        user=db_info['user'],
        password=db_info['password'],
        port=db_info['port'],
        database=db_info['database']
    )
    cursor = conn.cursor()

    try:
        # 下载圣经数据
        if not os.path.exists("bibles"):
            download_bibles()
        
        # 创建表
        create_tables(cursor)
        
        # 导入所有圣经文件
        for bible_file in Path("bibles").glob("*.xml"):
            try:
                import_bible(cursor, bible_file)
                conn.commit()
                print(f"成功导入 {bible_file}")
            except Exception as e:
                print(f"导入 {bible_file} 时出错: {e}")
                conn.rollback()
        
        print("导入完成！")
    
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    main() 