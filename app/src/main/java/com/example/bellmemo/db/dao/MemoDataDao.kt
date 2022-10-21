package com.example.bellmemo.db.dao

import androidx.room.Dao
import androidx.room.Insert
import com.example.bellmemo.db.entity.MemoData

@Dao
interface MemoDataDao {
    @Insert
    fun insertMemo(vararg memo:MemoData)
}