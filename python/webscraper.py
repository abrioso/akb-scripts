import scrapy
from scrapy.crawler import CrawlerProcess

class MySpider(scrapy.Spider):
    name = "my_spider"
    start_urls = [
        'http://www.iseg.ulisboa.pt/',
    ]

    def parse(self, response):
        for link in response.css('a'):
            yield {
                'link': link.css('::attr(href)').extract_first(),
                'text': link.css('::text').extract_first(),
                'page': response.url,
            }

def main():
    process = CrawlerProcess(settings={
        'FEEDS': {
            'output.json': {
                'format': 'json',
                'encoding': 'utf8',
                'store_empty': False,
                'indent': 4,
            },
        },
    })
    process.crawl(MySpider)
    process.start()

if __name__ == '__main__':
    main()