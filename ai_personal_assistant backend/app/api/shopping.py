"""
Shopping List API Endpoints
Manages shopping items
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel

from app.db.database import get_db
from app.db.models import ShoppingItem

router = APIRouter()


class ShoppingItemCreate(BaseModel):
    name: str
    quantity: str = "1"
    category: Optional[str] = None
    notes: Optional[str] = None
    price_estimate: Optional[float] = None


class ShoppingItemUpdate(BaseModel):
    name: Optional[str] = None
    quantity: Optional[str] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    price_estimate: Optional[float] = None
    is_purchased: Optional[bool] = None


@router.get("/")
async def list_shopping_items(
    purchased: Optional[bool] = None,
    category: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Get all shopping items"""
    query = db.query(ShoppingItem)
    
    if purchased is not None:
        query = query.filter(ShoppingItem.is_purchased == purchased)
    
    if category:
        query = query.filter(ShoppingItem.category == category)
    
    items = query.order_by(ShoppingItem.created_at.desc()).all()
    
    # Calculate total estimate
    total_estimate = sum(item.price_estimate or 0 for item in items if not item.is_purchased)
    
    return {
        "count": len(items),
        "total_estimate": total_estimate,
        "items": [
            {
                "id": item.id,
                "name": item.name,
                "quantity": item.quantity,
                "category": item.category,
                "notes": item.notes,
                "price_estimate": item.price_estimate,
                "is_purchased": item.is_purchased,
                "created_at": item.created_at.isoformat()
            }
            for item in items
        ]
    }


@router.post("/")
async def add_shopping_item(item: ShoppingItemCreate, db: Session = Depends(get_db)):
    """Add a new shopping item"""
    new_item = ShoppingItem(
        name=item.name,
        quantity=item.quantity,
        category=item.category,
        notes=item.notes,
        price_estimate=item.price_estimate
    )
    
    db.add(new_item)
    db.commit()
    db.refresh(new_item)
    
    return {
        "id": new_item.id,
        "name": new_item.name,
        "message": f"'{new_item.name}' added to shopping list"
    }


@router.put("/{item_id}")
async def update_shopping_item(
    item_id: int,
    item_update: ShoppingItemUpdate,
    db: Session = Depends(get_db)
):
    """Update a shopping item"""
    item = db.query(ShoppingItem).filter(ShoppingItem.id == item_id).first()
    
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    
    if item_update.name is not None:
        item.name = item_update.name
    if item_update.quantity is not None:
        item.quantity = item_update.quantity
    if item_update.category is not None:
        item.category = item_update.category
    if item_update.notes is not None:
        item.notes = item_update.notes
    if item_update.price_estimate is not None:
        item.price_estimate = item_update.price_estimate
    if item_update.is_purchased is not None:
        item.is_purchased = item_update.is_purchased
    
    db.commit()
    
    return {"success": True, "message": f"'{item.name}' updated"}


@router.delete("/{item_id}")
async def delete_shopping_item(item_id: int, db: Session = Depends(get_db)):
    """Delete a shopping item"""
    item = db.query(ShoppingItem).filter(ShoppingItem.id == item_id).first()
    
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    
    name = item.name
    db.delete(item)
    db.commit()
    
    return {"success": True, "message": f"'{name}' removed from list"}


@router.post("/{item_id}/purchase")
async def mark_purchased(item_id: int, db: Session = Depends(get_db)):
    """Mark item as purchased"""
    item = db.query(ShoppingItem).filter(ShoppingItem.id == item_id).first()
    
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    
    item.is_purchased = True
    db.commit()
    
    return {"success": True, "message": f"'{item.name}' marked as purchased"}


@router.post("/clear-purchased")
async def clear_purchased(db: Session = Depends(get_db)):
    """Remove all purchased items"""
    deleted = db.query(ShoppingItem).filter(ShoppingItem.is_purchased == True).delete()
    db.commit()
    
    return {"success": True, "message": f"{deleted} purchased items cleared"}
