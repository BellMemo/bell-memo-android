package com.example.bellmemo

import android.app.SearchManager
import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class SearchableActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.search)

        // Verify the action and get the query
        if (Intent.ACTION_SEARCH == intent.action) {
            intent.getStringExtra(SearchManager.QUERY)?.also { query ->
                doMysearch(query)
            }
        }
    }


    fun doMysearch(query: String) {
        println(query)
    }
}