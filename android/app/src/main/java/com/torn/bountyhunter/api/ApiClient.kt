package com.torn.bountyhunter.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object ApiClient {

    private val okHttp = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    val torn: TornApiService = Retrofit.Builder()
        .baseUrl("https://api.torn.com/")
        .client(okHttp)
        .addConverterFactory(GsonConverterFactory.create())
        .build()
        .create(TornApiService::class.java)

    val ffScouter: FFScouterApiService = Retrofit.Builder()
        .baseUrl("https://ffscouter.com/api/")
        .client(okHttp)
        .addConverterFactory(GsonConverterFactory.create())
        .build()
        .create(FFScouterApiService::class.java)

    /** Raw GET returning the response body as a String. Bypasses Gson. */
    suspend fun rawGet(url: String): String = withContext(Dispatchers.IO) {
        val req = okhttp3.Request.Builder().url(url).build()
        okHttp.newCall(req).execute().use { it.body!!.string() }
    }
}
