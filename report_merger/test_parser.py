import unittest
from parser import get_coverage_dicts_file, get_coverage_dicts_dir



class TestParser(unittest.TestCase):

    def test_get_coverage_dicts_file_test1(self):
        result = get_coverage_dicts_file('test_data/org.joda.time/test1.java.html')
        assert result == {
            110: {
                "class": ["fc","bfc"],
                "title": "All 4 branches covered."
            },
            111: {
                "class": ["fc","bfc"],
                "title": "All 4 branches covered."
            },
            112: {
                "class": ["fc","bfc"],
                "title": "All 2 branches covered."
            },
        }

    def test_get_coverage_dicts_file_test2(self):
        result = get_coverage_dicts_file('test_data/org.joda.time.base/test2.java.html')
        assert result == {
            127: {
                "class": ["fc","bfc"],
                "title": "All 2 branches covered."
            },
            128: {
                "class": ["fc"],
                "title": None
            },
            130: {
                "class": ["fc"],
                "title": None
            },
        }

    def test_get_coverage_dicts_file_test3(self):
        result = get_coverage_dicts_file('test_data/org.joda.time.chrono/test3.java.html')
        assert result == {
            159: {
                "class": ["fc"],
                "title": None
            },
            160: {
                "class": ["fc"],
                "title": None
            },
            163: {
                "class": ["fc"],
                "title": None
            },
        }

    def test_get_coverage_dicts_dir(self):
        result = get_coverage_dicts_dir('test_data')
        print(result)
        assert result == {
            'org.joda.time': {
                'test1.java': {
                    110: {
                        "class": ["fc", "bfc"],
                        "title": "All 4 branches covered."
                    },
                    111: {
                        "class": ["fc", "bfc"],
                        "title": "All 4 branches covered."
                    },
                    112: {
                        "class": ["fc", "bfc"],
                        "title": "All 2 branches covered."
                    },
                }
            },
            'org.joda.time.base': {
                'test2.java': {
                    127: {
                        "class": ["fc", "bfc"],
                        "title": "All 2 branches covered."
                    },
                    128: {
                        "class": ["fc"],
                        "title": None
                    },
                    130: {
                        "class": ["fc"],
                        "title": None
                    },
                }
            },
            'org.joda.time.chrono': {
                'test3.java': {
                    159: {
                        "class": ["fc"],
                        "title": None
                    },
                    160: {
                        "class": ["fc"],
                        "title": None
                    },
                    163: {
                        "class": ["fc"],
                        "title": None
                    },
                }
            }
        }



if __name__ == '__main__':
    unittest.main()
