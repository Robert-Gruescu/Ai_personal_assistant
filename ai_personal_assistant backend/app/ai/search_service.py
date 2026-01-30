"""
Internet Search Service
Provides web search capabilities for the AI assistant using DuckDuckGo
"""
from typing import Dict, List, Any
from duckduckgo_search import DDGS


class SearchService:
    """Handles internet searches for the AI"""
    
    def __init__(self):
        self.ddgs = None
    
    def _get_ddgs(self):
        """Get or create DuckDuckGo search instance"""
        if self.ddgs is None:
            self.ddgs = DDGS()
        return self.ddgs
    
    def search(self, query: str, num_results: int = 5) -> Dict[str, Any]:
        """
        Search the internet for information
        
        Args:
            query: Search query
            num_results: Number of results to return
            
        Returns:
            Dict with search results
        """
        try:
            ddgs = self._get_ddgs()
            
            # Search for text results
            results = list(ddgs.text(
                query,
                region="ro-ro",  # Romanian region
                safesearch="moderate",
                max_results=num_results
            ))
            
            formatted_results = []
            for item in results:
                formatted_results.append({
                    "title": item.get("title", ""),
                    "snippet": item.get("body", ""),
                    "link": item.get("href", "")
                })
            
            # Try to get instant answer
            direct_answer = None
            try:
                answers = list(ddgs.answers(query))
                if answers:
                    direct_answer = answers[0].get("text")
            except:
                pass
            
            return {
                "success": True,
                "query": query,
                "direct_answer": direct_answer,
                "results": formatted_results,
                "error": None
            }
            
        except Exception as e:
            print(f"Search error: {e}")
            return {
                "success": False,
                "query": query,
                "direct_answer": None,
                "results": [],
                "error": str(e)
            }
    
    def search_news(self, query: str, num_results: int = 5) -> Dict[str, Any]:
        """Search for news articles"""
        try:
            ddgs = self._get_ddgs()
            
            results = list(ddgs.news(
                query,
                region="ro-ro",
                safesearch="moderate",
                max_results=num_results
            ))
            
            formatted_results = []
            for item in results:
                formatted_results.append({
                    "title": item.get("title", ""),
                    "snippet": item.get("body", ""),
                    "link": item.get("url", ""),
                    "date": item.get("date", ""),
                    "source": item.get("source", "")
                })
            
            return {
                "success": True,
                "query": query,
                "results": formatted_results,
                "error": None
            }
            
        except Exception as e:
            return {
                "success": False,
                "query": query,
                "results": [],
                "error": str(e)
            }
    
    def format_results_for_ai(self, search_results: Dict[str, Any]) -> str:
        """Format search results as context for the AI"""
        if not search_results.get("success"):
            return f"Nu am putut căuta: {search_results.get('error', 'eroare necunoscută')}"
        
        parts = [f"Rezultate căutare pentru '{search_results['query']}':"]
        
        if search_results.get("direct_answer"):
            parts.append(f"\nRăspuns direct: {search_results['direct_answer']}")
        
        for i, result in enumerate(search_results.get("results", [])[:5], 1):
            title = result.get("title", "")
            snippet = result.get("snippet", "")
            parts.append(f"\n{i}. {title}")
            if snippet:
                parts.append(f"   {snippet[:200]}...")
        
        return "\n".join(parts)


# Singleton instance
search_service = SearchService()
