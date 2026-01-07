"""History manager for storing and cleaning up transcription history."""

import sqlite3
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional
from dataclasses import dataclass


@dataclass
class HistoryEntry:
    """A single history entry."""
    id: int
    text: str
    duration: float
    language: Optional[str]
    created_at: datetime


class HistoryManager:
    """Manages transcription history with SQLite storage."""

    def __init__(
        self,
        db_path: str = "~/.whisper_history.db",
        max_items: int = 50,
        retention_days: int = 7
    ):
        """
        Initialize the history manager.

        Args:
            db_path: Path to SQLite database file
            max_items: Maximum number of items to keep
            retention_days: Delete items older than this many days
        """
        self.db_path = Path(os.path.expanduser(db_path))
        self.max_items = max_items
        self.retention_days = retention_days
        self._init_db()

    def _init_db(self):
        """Initialize the database schema."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                CREATE TABLE IF NOT EXISTS history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    text TEXT NOT NULL,
                    duration REAL DEFAULT 0,
                    language TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            conn.execute('''
                CREATE INDEX IF NOT EXISTS idx_created_at ON history(created_at)
            ''')
            conn.commit()

    def add(
        self,
        text: str,
        duration: float = 0,
        language: Optional[str] = None
    ) -> int:
        """
        Add a new transcription to history.

        Args:
            text: Transcribed text
            duration: Audio duration in seconds
            language: Detected language code

        Returns:
            ID of the new entry
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute(
                '''INSERT INTO history (text, duration, language) VALUES (?, ?, ?)''',
                (text, duration, language)
            )
            entry_id = cursor.lastrowid
            conn.commit()

        # Run cleanup after adding
        self.cleanup()

        return entry_id

    def get_recent(self, limit: int = 10) -> list[HistoryEntry]:
        """
        Get recent history entries.

        Args:
            limit: Maximum number of entries to return

        Returns:
            List of HistoryEntry objects, most recent first
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(
                '''SELECT * FROM history ORDER BY created_at DESC LIMIT ?''',
                (limit,)
            )
            rows = cursor.fetchall()

        entries = []
        for row in rows:
            entries.append(HistoryEntry(
                id=row['id'],
                text=row['text'],
                duration=row['duration'],
                language=row['language'],
                created_at=datetime.fromisoformat(row['created_at'])
            ))

        return entries

    def get_by_id(self, entry_id: int) -> Optional[HistoryEntry]:
        """Get a specific history entry by ID."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(
                '''SELECT * FROM history WHERE id = ?''',
                (entry_id,)
            )
            row = cursor.fetchone()

        if row is None:
            return None

        return HistoryEntry(
            id=row['id'],
            text=row['text'],
            duration=row['duration'],
            language=row['language'],
            created_at=datetime.fromisoformat(row['created_at'])
        )

    def delete(self, entry_id: int):
        """Delete a specific history entry."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''DELETE FROM history WHERE id = ?''', (entry_id,))
            conn.commit()

    def clear(self):
        """Clear all history."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''DELETE FROM history''')
            conn.commit()

    def cleanup(self):
        """Remove old entries and enforce max items limit."""
        with sqlite3.connect(self.db_path) as conn:
            # Remove entries older than retention_days
            cutoff = datetime.now() - timedelta(days=self.retention_days)
            conn.execute(
                '''DELETE FROM history WHERE created_at < ?''',
                (cutoff.isoformat(),)
            )

            # Keep only max_items most recent
            conn.execute('''
                DELETE FROM history
                WHERE id NOT IN (
                    SELECT id FROM history
                    ORDER BY created_at DESC
                    LIMIT ?
                )
            ''', (self.max_items,))

            conn.commit()

    def count(self) -> int:
        """Get total number of history entries."""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute('''SELECT COUNT(*) FROM history''')
            return cursor.fetchone()[0]

    def search(self, query: str, limit: int = 10) -> list[HistoryEntry]:
        """
        Search history entries by text.

        Args:
            query: Search query
            limit: Maximum results

        Returns:
            Matching entries
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute(
                '''SELECT * FROM history WHERE text LIKE ? ORDER BY created_at DESC LIMIT ?''',
                (f'%{query}%', limit)
            )
            rows = cursor.fetchall()

        entries = []
        for row in rows:
            entries.append(HistoryEntry(
                id=row['id'],
                text=row['text'],
                duration=row['duration'],
                language=row['language'],
                created_at=datetime.fromisoformat(row['created_at'])
            ))

        return entries
