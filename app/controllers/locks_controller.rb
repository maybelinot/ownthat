class LocksController < ApplicationController
  include SmartListing::Helper::ControllerExtensions
  helper  SmartListing::Helper

  def index
    locks_scope = Lock.all
    locks_scope = locks_scope.like(params[:filter]) if params[:filter]

    @locks = smart_listing_create :locks, locks_scope, partial: "locks/list",
      default_sort: {namespace: "asc", resource: "asc"}
  end

  def new
    @lock = Lock.new
  end

  def create
    new_params = lock_params
    @lock = Lock.new(new_params)
    @lock.save
    @persisted = true
  rescue ActiveRecord::RecordNotUnique
    # try to update existing record in case it has expired
    update_params = {
      owner: new_params[:owner],
      expires: new_params[:expires]
    }
    num_updated = Lock.
      where(namespace: new_params[:namespace],
            resource: new_params[:resource]).
      where("expires < ?", Time.now).
      update_all(update_params)
    case num_updated
    when 1
      @persisted = true
    when 0
      @persisted = false
    else
      # this should be impossible
      raise "Unicorns ate the unique database index?"
    end
  end

  def edit
    @lock = Lock.find(params[:id])
  end

  def update
    if auth_admin?
      # allow any valid change but concurrency unsafe
      @lock = Lock.find(params[:id])
      @lock.update(lock_params)
      @persisted = true
    else
      # for non-admin allow only updating reservation time to prevent
      # lock stealing and other mistakes
      update_params = lock_params
      @lock = Lock.new(update_params)
      num_updated = Lock.
        where(owner: update_params[:owner],
              namespace: update_params[:namespace],
              resource: update_params[:resource]).
        update_all(expires: lock_params[:expires],
                   updated_at: Time.now)

      if num_updated == 1
        @persisted = true
      elsif num_updated == 0
        # concurrency issue or not matching owner/resource specification
        @persisted = false
      else
        # this should be impossible
        raise "Unicorns ate the unique database index?"
      end
    end
  end

  def destroy
    @lock = Lock.find(params[:id])
    @lock.destroy
  end

  private

  def find_lock
    @lock = Lock.find(params[:id])
  end

  def lock_params
    if params[:lock][:expires].kind_of?(String) &&
        params[:lock][:expires] =~ /^(\d+)([smhd])?$/ ||
        params[:lock][:expires].kind_of?(Numeric)
      # using duration notation
      count = $1 ? Integer($1) : params[:lock][:expires]
      case $2
      when nil, "s"
        # count = count
      when "m"
        count = count * 60
      when "h"
        count = count * 60 * 60
      when "d"
        count = count * 60 * 60 * 24
      end
      params[:lock] = params[:lock].merge({expires: Time.now + count})
    elsif params[:lock][:expires].kind_of?(String)
      params[:lock][:expires] = Time.parse params[:lock][:expires]
    end

    params.require(:lock).permit(:namespace, :resource, :expires, :owner)
  end
end
