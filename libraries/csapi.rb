module ApiLib
  require 'rubygems'
  require 'cloudstack_helper'
  require 'json'

  def setup_csapi(url='',apikey='',seckey='')
    if ( url !~ /^https?\:\/\/.*\/api\/$/ ) then
      abort("Malformed Cloudstack API url")
    else
      if ( apikey == '' || seckey=='' ) then
        abort("No API key or SECRET key provided")
      end
    end

    return  CloudStackHelper.new(:api_url => url,:api_key => apikey,:secret_key => seckey)
  end

  def csapi_do(api = nil,params = nil, abort_on_error = false)
    if ( api == nil || params == nil ) then
      abort("No api object or parameter block provided")
    end

    params[:response] = 'json'

    json = ""
    begin
      json = api.get(params).body
    rescue
      error = "Cloud Stck API returned an error: #{$!}"
      Chef::Log.error(error)
      if ( abort_on_error ) then
        abort(error)
      else
        return nil
      end
    end

    return JSON.parse(json)
  end
end
