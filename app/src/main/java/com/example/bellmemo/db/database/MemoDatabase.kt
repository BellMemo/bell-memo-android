package com.example.bellmemo.db.database

import androidx.room.Database
import androidx.room.RoomDatabase
import com.example.bellmemo.db.dao.MemoDataDao
import com.example.bellmemo.db.entity.MemoData

@Database(entities = [MemoData::class], version = 1)
abstract class MemoDatabase: RoomDatabase() {
    abstract fun MemoDataDao(): MemoDataDao
}